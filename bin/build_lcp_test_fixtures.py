"""Generates Readium LCP basic-profile test fixtures from unprotected fixtures.

Run through bin/build_lcp_test_fixtures, which supplies the passphrase and installs
`cryptography` via uvx. The basic profile (http://readium.org/lcp/basic-profile) is
"for test only" in the LCP spec: SHA-256 user key, AES-256-CBC, RSA-SHA256 signature.

Output files (all under --out-dir, which is gitignored):
  lcp_peter_rabbit.epub           protected EPUB, license at META-INF/license.lcpl
  lcp_38533.lcpa                  protected audiobook, license at license.lcpl
  lcp_pdf_test.lcpdf              protected PDF, license at license.lcpl
  lcp_acquire_peter_rabbit.epub   protected EPUB without a license (what a server delivers)
  lcp_acquire_peter_rabbit.lcpl   standalone license whose publication link points at it
  lcp_test_root_ca.{der,pem}      throwaway root CA (public), for verifying the licenses

Keys are generated per run and never written to disk; only the root CA certificate is.

Format facts, checked against swift-toolkit 3.11.0 and kotlin-toolkit 3.4.0 sources:
- Resource layout is IV (16 bytes) || AES-CBC ciphertext, padded with PKCS#7 (last byte =
  pad length, 1..16, a full block when already aligned). Swift:
  Sources/LCP/Content Protection/LCPDecryptor.swift (isValidAESChunk: >= 2 blocks, multiple
  of 16; decryptFully strips `data[count - 1]` bytes after decipher). Kotlin:
  readium/lcp/.../LcpDecryptor.kt (decryptFully; CbcLcpResource length = size - IV - pad).
  The AES itself runs inside the private client library, so the toolkits only confirm the
  framing. Content key, key_check and signature follow the spec and the LCP server
  convention (same IV||ciphertext framing, SHA-256 hex passed as `hashedPassphrase`); the
  toolkit sources do not verify those.
- Deflated resources need BOTH Method="8" and OriginalLength in encryption.xml; any other
  Method means "not deflated". Swift: Sources/LCP/Content Protection/EncryptionParser.swift.
  Inflate is raw deflate (Kotlin: `inflate(nowrap = true)`).
- EPUB encryption.xml is read via enc:EncryptedData/ds:RetrievalMethod URI
  "license.lcpl#/encryption/content_key" and comp:Compression (same Swift file). RPF
  packages (.lcpa, .lcpdf) use `properties.encrypted` {scheme, algorithm, originalLength}
  on readingOrder links; scheme must be "http://readium.org/2014/01/lcp".
- Swift (LicenseDocument.swift) needs provider, id, issued, encryption, links with a
  `publication` link, signature. Kotlin (LicenseDocument.kt) also needs a `hint` link.
  `length` must be an integer (Link.swift, Link.kt).
- Neither toolkit checks the publication link `hash` or `length` on acquisition. The LCP
  link schema says base64 SHA-256 (the spec's example shows hex); this script writes base64.
"""

import argparse
import base64
import copy
import datetime
import hashlib
import io
import json
import mimetypes
import os
import posixpath
import re
import sys
import uuid
import zipfile
import zlib
from urllib.parse import quote, unquote
from xml.etree import ElementTree as ET
from xml.sax.saxutils import quoteattr

from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, padding, serialization
from cryptography.hazmat.primitives.asymmetric import padding as asym_padding
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.x509.oid import NameOID

PROFILE = "http://readium.org/lcp/basic-profile"
ALG_AES = "http://www.w3.org/2001/04/xmlenc#aes256-cbc"
ALG_SHA256 = "http://www.w3.org/2001/04/xmlenc#sha256"
ALG_SIGNATURE = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
SCHEME = "http://readium.org/2014/01/lcp"
KEY_INFO_TYPE = "http://readium.org/2014/01/lcp#EncryptedContentKey"
NS_CONTAINER = "urn:oasis:names:tc:opendocument:xmlns:container"
NS_ENC = "http://www.w3.org/2001/04/xmlenc#"
NS_DS = "http://www.w3.org/2000/09/xmldsig#"
NS_COMP = "http://www.idpf.org/2016/encryption#compression"
NS_OPF = "http://www.idpf.org/2007/opf"

PROVIDER = "https://github.com/Notalib/flutter_readium"
HINT_URL = "https://github.com/Notalib/flutter_readium"
MIME_EPUB = "application/epub+zip"
MIME_LCPA = "application/audiobook+lcp"
MIME_LCPDF = "application/pdf+lcp"

SOURCES = {
    "epub": "peter_rabbit.epub",
    "lcpa": "38533.audiobook",
    "lcpdf": "pdf_test.pdf",
}
OUTPUTS = {
    "epub": "lcp_peter_rabbit.epub",
    "lcpa": "lcp_38533.lcpa",
    "lcpdf": "lcp_pdf_test.lcpdf",
    "acquire_pkg": "lcp_acquire_peter_rabbit.epub",
    "acquire_lcpl": "lcp_acquire_peter_rabbit.lcpl",
    "root_der": "lcp_test_root_ca.der",
    "root_pem": "lcp_test_root_ca.pem",
}
PDF_ENTRY = "publication.pdf"


# --- crypto primitives -------------------------------------------------------


def aes_encrypt(key, plaintext):
    iv = os.urandom(16)
    padder = padding.PKCS7(128).padder()
    padded = padder.update(plaintext) + padder.finalize()
    enc = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor()
    return iv + enc.update(padded) + enc.finalize()


def aes_decrypt(key, blob):
    """Inverse of aes_encrypt; stricter than the toolkits (checks every pad byte)."""
    if len(blob) < 32 or len(blob) % 16:
        raise ValueError(f"not a valid CBC blob ({len(blob)} bytes)")
    dec = Cipher(algorithms.AES(key), modes.CBC(blob[:16])).decryptor()
    padded = dec.update(blob[16:]) + dec.finalize()
    pad = padded[-1]
    if not 1 <= pad <= 16 or padded[-pad:] != bytes([pad]) * pad:
        raise ValueError("invalid PKCS#7 padding")
    return padded[:-pad]


def deflate(data):
    c = zlib.compressobj(9, zlib.DEFLATED, -15)
    return c.compress(data) + c.flush()


def inflate(data):
    return zlib.decompress(data, -15)


def user_key(passphrase):
    return hashlib.sha256(passphrase.encode("utf-8")).digest()


def b64(data):
    return base64.b64encode(data).decode("ascii")


# --- license document --------------------------------------------------------


def _json_str(s):
    if any(ord(ch) < 0x20 for ch in s):
        raise ValueError("control characters are not supported in license strings")
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def canonical(obj):
    """Canonical JSON per LCP spec 5.3: sorted keys, no whitespace, minimal escaping."""
    if isinstance(obj, dict):
        return "{" + ",".join(f"{_json_str(k)}:{canonical(obj[k])}" for k in sorted(obj)) + "}"
    if isinstance(obj, list):
        return "[" + ",".join(canonical(v) for v in obj) + "]"
    if obj is True:
        return "true"
    if obj is False:
        return "false"
    if obj is None:
        return "null"
    if isinstance(obj, int):
        return str(obj)
    if isinstance(obj, str):
        return _json_str(obj)
    raise ValueError(f"unsupported value in license: {obj!r}")


def utc_iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(s):
    return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)


class Pki:
    """Throwaway root CA and provider certificate, held in memory only."""

    def __init__(self, now):
        def key():
            return rsa.generate_private_key(public_exponent=65537, key_size=2048)

        def name(cn):
            return x509.Name(
                [
                    x509.NameAttribute(NameOID.ORGANIZATION_NAME, "flutter_readium LCP test"),
                    x509.NameAttribute(NameOID.COMMON_NAME, cn),
                ]
            )

        def usage(**kw):
            flags = dict(
                digital_signature=False, content_commitment=False, key_encipherment=False,
                data_encipherment=False, key_agreement=False, key_cert_sign=False,
                crl_sign=False, encipher_only=False, decipher_only=False,
            )
            flags.update(kw)
            return x509.KeyUsage(**flags)

        not_before = now - datetime.timedelta(days=1)
        not_after = now + datetime.timedelta(days=3650)
        root_name = name("flutter_readium LCP test root CA")
        self.root_key = key()
        self.root_cert = (
            x509.CertificateBuilder()
            .subject_name(root_name)
            .issuer_name(root_name)
            .public_key(self.root_key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(not_before)
            .not_valid_after(not_after)
            .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
            .add_extension(usage(key_cert_sign=True, crl_sign=True), critical=True)
            .sign(self.root_key, hashes.SHA256())
        )
        self.provider_key = key()
        self.provider_cert = (
            x509.CertificateBuilder()
            .subject_name(name("flutter_readium LCP test provider"))
            .issuer_name(root_name)
            .public_key(self.provider_key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(not_before)
            .not_valid_after(not_after)
            .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
            .add_extension(usage(digital_signature=True), critical=True)
            .sign(self.root_key, hashes.SHA256())
        )

    def sign(self, data):
        return self.provider_key.sign(data, asym_padding.PKCS1v15(), hashes.SHA256())

    def provider_der(self):
        return self.provider_cert.public_bytes(serialization.Encoding.DER)


def make_license(pki, passphrase, hint, content_key, issued, publication):
    """Returns a signed license document (dict). `publication` is the publication link."""
    license_id = str(uuid.uuid4())
    ukey = user_key(passphrase)
    doc = {
        "id": license_id,
        "issued": utc_iso(issued),
        "updated": utc_iso(issued),
        "provider": PROVIDER,
        "encryption": {
            "profile": PROFILE,
            "content_key": {
                "algorithm": ALG_AES,
                "encrypted_value": b64(aes_encrypt(ukey, content_key)),
            },
            "user_key": {
                "algorithm": ALG_SHA256,
                "text_hint": hint,
                "key_check": b64(aes_encrypt(ukey, license_id.encode("utf-8"))),
            },
        },
        "links": [
            publication,
            {"rel": "hint", "href": HINT_URL, "type": "text/html"},
        ],
        "user": {"id": "flutter-readium-test-user", "name": "Test Reader"},
    }
    doc["signature"] = {
        "algorithm": ALG_SIGNATURE,
        "certificate": b64(pki.provider_der()),
        "value": b64(pki.sign(canonical(doc).encode("utf-8"))),
    }
    return doc


def license_bytes(doc):
    return canonical(doc).encode("utf-8")


# --- EPUB --------------------------------------------------------------------


def epub_layout(z):
    """Returns (paths that must stay in clear, {path: media type}) for an EPUB."""
    container = ET.fromstring(z.read("META-INF/container.xml"))
    clear = {"mimetype"}
    media = {}
    for rootfile in container.iter(f"{{{NS_CONTAINER}}}rootfile"):
        opf_path = rootfile.get("full-path")
        clear.add(opf_path)
        base = posixpath.dirname(opf_path)
        opf = ET.fromstring(z.read(opf_path))
        cover_ids = {m.get("content") for m in opf.iter(f"{{{NS_OPF}}}meta") if m.get("name") == "cover"}
        for item in opf.iter(f"{{{NS_OPF}}}item"):
            path = posixpath.normpath(posixpath.join(base, unquote(item.get("href"))))
            media[path] = item.get("media-type")
            props = (item.get("properties") or "").split()
            if (
                "nav" in props
                or "cover-image" in props
                or item.get("media-type") == "application/x-dtbncx+xml"
                or item.get("id") in cover_ids
            ):
                clear.add(path)
    return clear, media


def is_codec(media_type):
    """Codec content is stored without deflate (spec 2.2)."""
    if media_type == "image/svg+xml":
        return False
    return media_type.startswith(("image/", "audio/", "video/")) or media_type in (
        "font/woff", "font/woff2", "application/font-woff", "application/font-woff2",
    )


def media_type_of(path, media):
    return media.get(path) or mimetypes.guess_type(path)[0] or "application/octet-stream"


def is_clear(path, clear):
    return path in clear or path.startswith("META-INF/")


def encryption_xml(entries):
    out = [
        '<?xml version="1.0" encoding="UTF-8"?>\n',
        f'<encryption xmlns="{NS_CONTAINER}" xmlns:enc="{NS_ENC}" xmlns:ds="{NS_DS}" '
        f'xmlns:comp="{NS_COMP}">\n',
    ]
    for path, method, original_length in entries:
        out.append(
            "  <enc:EncryptedData>\n"
            f'    <enc:EncryptionMethod Algorithm="{ALG_AES}"/>\n'
            "    <ds:KeyInfo>\n"
            f'      <ds:RetrievalMethod URI="license.lcpl#/encryption/content_key" Type="{KEY_INFO_TYPE}"/>\n'
            "    </ds:KeyInfo>\n"
            "    <enc:CipherData>\n"
            f"      <enc:CipherReference URI={quoteattr(quote(path))}/>\n"
            "    </enc:CipherData>\n"
            "    <enc:EncryptionProperties>\n"
            "      <enc:EncryptionProperty>\n"
            f'        <comp:Compression Method="{method}" OriginalLength="{original_length}"/>\n'
            "      </enc:EncryptionProperty>\n"
            "    </enc:EncryptionProperties>\n"
            "  </enc:EncryptedData>\n"
        )
    out.append("</encryption>\n")
    return "".join(out).encode("utf-8")


def write_zip(entries):
    """entries: list of (name, bytes, deflate?). Callers list `mimetype` first when needed."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for name, data, compress in entries:
            z.writestr(name, data, zipfile.ZIP_DEFLATED if compress else zipfile.ZIP_STORED)
    return buf.getvalue()


def build_epub(src_path, content_key, license_doc):
    """Protects an EPUB. `license_doc` None produces a package without license.lcpl."""
    with zipfile.ZipFile(src_path) as z:
        clear, media = epub_layout(z)
        if "META-INF/encryption.xml" in z.namelist():
            raise SystemExit(f"{src_path} already has META-INF/encryption.xml")
        entries = []
        enc_entries = []
        for info in z.infolist():
            if info.is_dir():
                continue
            name, data = info.filename, z.read(info)
            if is_clear(name, clear):
                entries.append((name, data, name != "mimetype" and info.compress_type != zipfile.ZIP_STORED))
                continue
            deflated = not is_codec(media_type_of(name, media))
            payload = deflate(data) if deflated else data
            entries.append((name, aes_encrypt(content_key, payload), False))
            enc_entries.append((name, 8 if deflated else 0, len(data)))
    entries.append(("META-INF/encryption.xml", encryption_xml(enc_entries), True))
    if license_doc is not None:
        entries.append(("META-INF/license.lcpl", license_bytes(license_doc), True))
    return write_zip(entries)


# --- RPF (.lcpa, .lcpdf) -----------------------------------------------------


def encrypted_properties(length):
    return {"scheme": SCHEME, "algorithm": ALG_AES, "originalLength": length}


def count_pdf_pages(data):
    pages = len(re.findall(rb"/Type\s*/Page\b(?!s)", data))
    if not pages:
        raise SystemExit("cannot count PDF pages; set numberOfPages by hand")
    return pages


def build_lcpa(src_path, content_key, license_doc):
    with zipfile.ZipFile(src_path) as z:
        manifest = json.loads(z.read("manifest.json"))
        encrypted = {}
        for link in manifest["readingOrder"]:
            data = z.read(link["href"])
            link["size"] = len(data)
            link.setdefault("properties", {})["encrypted"] = encrypted_properties(len(data))
            encrypted[link["href"]] = aes_encrypt(content_key, data)
        entries = [("manifest.json", json.dumps(manifest, indent=2, ensure_ascii=False).encode(), True)]
        for info in z.infolist():
            if info.filename == "manifest.json" or info.is_dir():
                continue
            entries.append((info.filename, encrypted.get(info.filename) or z.read(info), False))
    entries.append(("license.lcpl", license_bytes(license_doc), True))
    return write_zip(entries)


def build_lcpdf(src_path, content_key, license_doc):
    with open(src_path, "rb") as f:
        pdf = f.read()
    manifest = {
        "@context": "https://readium.org/webpub-manifest/context.jsonld",
        "metadata": {
            "@type": "http://schema.org/Book",
            "conformsTo": "https://readium.org/webpub-manifest/profiles/pdf",
            "identifier": f"urn:uuid:{uuid.uuid4()}",
            "title": "PDF Support Test (LCP)",
            "language": "en",
            "numberOfPages": count_pdf_pages(pdf),
        },
        "links": [{"rel": "self", "href": "manifest.json", "type": "application/webpub+json"}],
        "readingOrder": [
            {
                "href": PDF_ENTRY,
                "type": "application/pdf",
                "size": len(pdf),
                "properties": {"encrypted": encrypted_properties(len(pdf))},
            }
        ],
    }
    return write_zip(
        [
            ("manifest.json", json.dumps(manifest, indent=2).encode(), True),
            (PDF_ENTRY, aes_encrypt(content_key, pdf), False),
            ("license.lcpl", license_bytes(license_doc), True),
        ]
    )


# --- generation --------------------------------------------------------------


def write_file(path, data):
    with open(path, "wb") as f:
        f.write(data)


def generate(args):
    now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
    pki = Pki(now)
    out = args.out_dir
    os.makedirs(out, exist_ok=True)
    base = args.base_url.rstrip("/")

    def publication_link(key, mime, extra=None):
        link = {"rel": "publication", "href": f"{base}/{OUTPUTS[key]}", "type": mime}
        link.update(extra or {})
        return link

    def src(kind):
        path = os.path.join(args.src_dir, SOURCES[kind])
        if not os.path.isfile(path):
            raise SystemExit(f"missing source fixture {path}; run bin/fetch_test_resources")
        return path

    def protect(kind, builder, mime):
        key = os.urandom(32)
        doc = make_license(pki, args.passphrase, args.hint, key, now, publication_link(kind, mime))
        write_file(os.path.join(out, OUTPUTS[kind]), builder(src(kind), key, doc))

    protect("epub", build_epub, MIME_EPUB)
    protect("lcpa", build_lcpa, MIME_LCPA)
    protect("lcpdf", build_lcpdf, MIME_LCPDF)

    # Acquisition pair: the package carries no license, the .lcpl describes where to get it.
    key = os.urandom(32)
    package = build_epub(src("epub"), key, None)
    write_file(os.path.join(out, OUTPUTS["acquire_pkg"]), package)
    link = publication_link(
        "acquire_pkg",
        MIME_EPUB,
        {"length": len(package), "hash": b64(hashlib.sha256(package).digest())},
    )
    doc = make_license(pki, args.passphrase, args.hint, key, now, link)
    write_file(os.path.join(out, OUTPUTS["acquire_lcpl"]), license_bytes(doc))

    der = pki.root_cert.public_bytes(serialization.Encoding.DER)
    write_file(os.path.join(out, OUTPUTS["root_der"]), der)
    write_file(os.path.join(out, OUTPUTS["root_pem"]), pki.root_cert.public_bytes(serialization.Encoding.PEM))


# --- verification ------------------------------------------------------------


class Checker:
    def __init__(self):
        self.failures = []

    def check(self, condition, message):
        if not condition:
            self.failures.append(message)
            print(f"  FAIL {message}")
        return condition

    def guard(self, label, fn):
        """Runs fn; an exception counts as a failure of `label`."""
        try:
            return fn()
        except Exception as e:  # noqa: BLE001 - any failure here is a verification failure
            self.check(False, f"{label}: {type(e).__name__}: {e}")
            return None


def verify_license(c, label, doc, root, passphrase, base_url, pkg_filename):
    """Returns the decrypted content key, or None."""
    sig = doc.get("signature", {})
    c.check(sig.get("algorithm") == ALG_SIGNATURE, f"{label}: signature algorithm")
    body = {k: v for k, v in doc.items() if k != "signature"}
    cert = x509.load_der_x509_certificate(base64.b64decode(sig["certificate"]))

    try:
        root.public_key().verify(
            cert.signature, cert.tbs_certificate_bytes, asym_padding.PKCS1v15(), cert.signature_hash_algorithm
        )
        cert.public_key().verify(
            base64.b64decode(sig["value"]), canonical(body).encode("utf-8"), asym_padding.PKCS1v15(), hashes.SHA256()
        )
    except InvalidSignature:
        c.check(False, f"{label}: license or certificate signature invalid")
    issued = parse_iso(doc["issued"])
    c.check(cert.not_valid_before_utc <= issued <= cert.not_valid_after_utc, f"{label}: certificate validity vs issued")

    enc = doc["encryption"]
    c.check(enc["profile"] == PROFILE, f"{label}: profile")
    c.check(enc["content_key"]["algorithm"] == ALG_AES, f"{label}: content key algorithm")
    c.check(enc["user_key"]["algorithm"] == ALG_SHA256, f"{label}: user key algorithm")
    ukey = user_key(passphrase)
    checked = c.guard(f"{label}: key_check", lambda: aes_decrypt(ukey, base64.b64decode(enc["user_key"]["key_check"])))
    c.check(checked == doc["id"].encode("utf-8"), f"{label}: key_check does not decrypt to the license id")

    def wrong_key_rejected():
        try:
            return aes_decrypt(user_key(passphrase + "x"), base64.b64decode(enc["user_key"]["key_check"])) != doc["id"].encode()
        except ValueError:
            return True

    c.check(wrong_key_rejected(), f"{label}: wrong passphrase must not pass key_check")
    content_key = c.guard(f"{label}: content key", lambda: aes_decrypt(ukey, base64.b64decode(enc["content_key"]["encrypted_value"])))
    c.check(content_key is not None and len(content_key) == 32, f"{label}: content key is not 32 bytes")

    rels = [rel for link in doc["links"] for rel in ([link["rel"]] if isinstance(link["rel"], str) else link["rel"])]
    c.check("publication" in rels and "hint" in rels, f"{label}: needs publication and hint links")
    c.check("status" not in rels, f"{label}: unexpected status link")
    publication = next(link for link in doc["links"] if link["rel"] == "publication")
    c.check(publication["href"] == f"{base_url}/{pkg_filename}", f"{label}: publication href is {publication['href']}")
    return content_key, publication


def verify_epub(c, label, out_path, src_path, content_key, expect_license):
    with zipfile.ZipFile(out_path) as zo, zipfile.ZipFile(src_path) as zs:
        names = [i.filename for i in zo.infolist()]
        c.check(names[0] == "mimetype" and zo.infolist()[0].compress_type == zipfile.ZIP_STORED, f"{label}: mimetype first and stored")
        has_license = "META-INF/license.lcpl" in names
        c.check(has_license == expect_license, f"{label}: license presence")
        extra = {"META-INF/encryption.xml"} | ({"META-INF/license.lcpl"} if expect_license else set())
        c.check(set(names) - extra == {i.filename for i in zs.infolist() if not i.is_dir()}, f"{label}: entry set")
        clear, media = epub_layout(zs)

        root = ET.fromstring(zo.read("META-INF/encryption.xml"))
        encrypted = {}
        for ed in root.iter(f"{{{NS_ENC}}}EncryptedData"):
            uri = unquote(ed.find(f"{{{NS_ENC}}}CipherData/{{{NS_ENC}}}CipherReference").get("URI"))
            rm = ed.find(f"{{{NS_DS}}}KeyInfo/{{{NS_DS}}}RetrievalMethod")
            c.check(rm.get("URI") == "license.lcpl#/encryption/content_key" and rm.get("Type") == KEY_INFO_TYPE, f"{label}: key info for {uri}")
            c.check(ed.find(f"{{{NS_ENC}}}EncryptionMethod").get("Algorithm") == ALG_AES, f"{label}: algorithm for {uri}")
            comp = ed.find(f".//{{{NS_COMP}}}Compression")
            encrypted[uri] = (comp.get("Method"), int(comp.get("OriginalLength")))

        for name in names:
            if name == "META-INF/encryption.xml" or (expect_license and name == "META-INF/license.lcpl"):
                continue
            original = zs.read(name)
            if is_clear(name, clear):
                c.check(name not in encrypted, f"{label}: {name} must not be encrypted")
                c.check(zo.read(name) == original, f"{label}: {name} (clear) differs from source")
                continue
            if not c.check(name in encrypted, f"{label}: {name} should be encrypted"):
                continue
            method, original_length = encrypted[name]
            deflated = not is_codec(media_type_of(name, media))
            c.check(method == ("8" if deflated else "0"), f"{label}: {name} compression method {method}")
            c.check(original_length == len(original), f"{label}: {name} OriginalLength")
            plain = c.guard(f"{label}: {name} decrypt", lambda: aes_decrypt(content_key, zo.read(name)))
            if plain is not None:
                plain = c.guard(f"{label}: {name} inflate", lambda: inflate(plain)) if method == "8" else plain
            c.check(plain == original, f"{label}: {name} differs from source after decryption")
        c.check(set(encrypted) <= set(names), f"{label}: encryption.xml references missing entries")
        return len(encrypted)


def verify_rpf(c, label, out_path, src_zip, src_pdf, content_key):
    """Verifies .lcpa (src_zip) or .lcpdf (src_pdf) packages. Returns the encrypted count."""
    with zipfile.ZipFile(out_path) as zo:
        names = [i.filename for i in zo.infolist()]
        c.check(names[0] == "manifest.json" and "license.lcpl" in names, f"{label}: manifest.json first, license.lcpl at root")
        manifest = json.loads(zo.read("manifest.json"))
        links = manifest["readingOrder"] + manifest.get("resources", [])
        count = 0
        for link in links:
            enc = link.get("properties", {}).get("encrypted")
            href = link["href"]
            if enc is None:
                continue
            count += 1
            c.check(enc["scheme"] == SCHEME and enc["algorithm"] == ALG_AES, f"{label}: encrypted props of {href}")
            c.check("compression" not in enc, f"{label}: {href} must not be compressed")
            c.check(zo.getinfo(href).compress_type == zipfile.ZIP_STORED, f"{label}: {href} must be stored in the zip")
            original = src_pdf if src_zip is None else None
            if src_zip is not None:
                with zipfile.ZipFile(src_zip) as zs:
                    original = zs.read(href)
            plain = c.guard(f"{label}: {href} decrypt", lambda: aes_decrypt(content_key, zo.read(href)))
            c.check(plain == original, f"{label}: {href} differs from source after decryption")
            c.check(enc.get("originalLength") == len(original) and link.get("size") == len(original), f"{label}: {href} size metadata")
        c.check(count == len(manifest["readingOrder"]), f"{label}: every readingOrder item must be encrypted")
        c.check(not any(r.get("properties", {}).get("encrypted") for r in manifest.get("resources", [])), f"{label}: resources (cover) must stay clear")
        if src_zip is not None:
            with zipfile.ZipFile(src_zip) as zs:
                stripped = copy.deepcopy(manifest)
                for link in stripped["readingOrder"]:
                    link.pop("size", None)
                    link["properties"].pop("encrypted")
                    if not link["properties"]:
                        del link["properties"]
                c.check(stripped == json.loads(zs.read("manifest.json")), f"{label}: manifest differs from source beyond encryption")
                for name in names:
                    if name not in ("manifest.json", "license.lcpl") and not any(l["href"] == name for l in links if l.get("properties", {}).get("encrypted")):
                        c.check(zo.read(name) == zs.read(name), f"{label}: {name} (clear) differs from source")
        else:
            c.check("pdf" in " ".join(manifest["metadata"]["conformsTo"] if isinstance(manifest["metadata"]["conformsTo"], list) else [manifest["metadata"]["conformsTo"]]), f"{label}: conformsTo pdf profile")
            c.check(manifest["metadata"]["numberOfPages"] == count_pdf_pages(src_pdf), f"{label}: numberOfPages")
        return count


def verify(args):
    c = Checker()
    out = args.out_dir
    base = args.base_url.rstrip("/")

    def path(key):
        return os.path.join(out, OUTPUTS[key])

    def read(p):
        with open(p, "rb") as f:
            return f.read()

    for key in OUTPUTS:
        if not os.path.isfile(path(key)):
            raise SystemExit(f"missing output {path(key)}; run without --verify first")

    root = x509.load_der_x509_certificate(read(path("root_der")))
    c.check(
        root.public_bytes(serialization.Encoding.PEM) == read(path("root_pem")),
        "root CA PEM and DER differ",
    )
    src = {k: os.path.join(args.src_dir, v) for k, v in SOURCES.items()}
    summary = []

    def embedded(kind, license_name):
        with zipfile.ZipFile(path(kind)) as z:
            return json.loads(z.read(license_name))

    for kind, license_name in (("epub", "META-INF/license.lcpl"), ("lcpa", "license.lcpl"), ("lcpdf", "license.lcpl")):
        label = OUTPUTS[kind]
        doc = embedded(kind, license_name)
        key, _ = verify_license(c, label, doc, root, args.passphrase, base, label)
        if key is None:
            continue
        if kind == "epub":
            n = verify_epub(c, label, path(kind), src["epub"], key, True)
        elif kind == "lcpa":
            n = verify_rpf(c, label, path(kind), src["lcpa"], None, key)
        else:
            n = verify_rpf(c, label, path(kind), None, read(src["lcpdf"]), key)
        summary.append(f"{label}: {n} encrypted resources")

    lcpl = json.loads(read(path("acquire_lcpl")))
    key, link = verify_license(c, OUTPUTS["acquire_lcpl"], lcpl, root, args.passphrase, base, OUTPUTS["acquire_pkg"])
    package = read(path("acquire_pkg"))
    c.check(link.get("type") == MIME_EPUB, "acquire: publication link type")
    c.check(link.get("length") == len(package), "acquire: publication link length")
    c.check(link.get("hash") == b64(hashlib.sha256(package).digest()), "acquire: publication link hash")
    if key is not None:
        n = verify_epub(c, OUTPUTS["acquire_pkg"], path("acquire_pkg"), src["epub"], key, False)
        summary.append(f"{OUTPUTS['acquire_pkg']}: {n} encrypted resources, link hash/length ok")

    if c.failures:
        print(f"Verification FAILED ({len(c.failures)} problem(s))", file=sys.stderr)
        sys.exit(1)
    for line in summary:
        print(f"  ok {line}")
    print("Verification passed: signatures, key_check, content keys, bytes and link hash all match.")


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--passphrase", required=True)
    p.add_argument("--hint", required=True)
    p.add_argument("--src-dir", required=True)
    p.add_argument("--out-dir", required=True)
    p.add_argument("--base-url", default="http://127.0.0.1:8765")
    p.add_argument("--verify", action="store_true", help="only verify existing outputs")
    args = p.parse_args()
    if not args.verify:
        generate(args)
    verify(args)


if __name__ == "__main__":
    main()
