package dk.nota.flutterreadiumlcp

import dk.nota.flutterreadium.FlutterReadiumCustomError
import io.flutter.plugin.common.MethodChannel
import org.readium.r2.lcp.LcpError
import org.readium.r2.shared.util.Error

/** Turns the toolkit's protection error into the wire codes `LcpErrorCodes` documents on the Dart side. */
internal object LcpErrors {
    /** Fails a method-channel [result] with the wire code and details of [error]. */
    fun report(
        result: MethodChannel.Result,
        error: Error?,
    ) {
        val custom = map(error)
        result.error(custom.code, custom.message, custom.data)
    }

    /** [error] is null when the user cancelled the passphrase prompt: the toolkit hides that case. */
    fun map(error: Error?): FlutterReadiumCustomError =
        when (error) {
            null, is LcpError.MissingPassphrase -> {
                FlutterReadiumCustomError("lcpPassphraseRequired", "A passphrase is required to open this publication.")
            }

            is LcpError.LicenseIntegrity.CertificateRevoked,
            is LcpError.LicenseIntegrity.InvalidCertificateSignature,
            is LcpError.LicenseIntegrity.InvalidLicenseSignatureDate,
            is LcpError.LicenseIntegrity.InvalidLicenseSignature,
            is LcpError.Parsing.Signature,
            -> {
                licenseInvalid("signature", error)
            }

            is LcpError.LicenseIntegrity -> {
                licenseInvalid("integrity", error)
            }

            is LcpError.LicenseProfileNotSupported -> {
                licenseInvalid("profileNotSupported", error)
            }

            is LcpError.Parsing, is LcpError.Container -> {
                licenseInvalid("malformed", error)
            }

            is LcpError.LicenseStatus -> {
                licenseStatus(error)
            }

            is LcpError.CrlFetching -> {
                FlutterReadiumCustomError(
                    "lcpNetwork",
                    "Could not fetch the certificate revocation list.",
                    mapOf("reason" to "crl"),
                )
            }

            is LcpError.Network -> {
                FlutterReadiumCustomError(
                    "lcpNetwork",
                    "A network request for the license failed.",
                    mapOf("reason" to "network"),
                )
            }

            else -> {
                FlutterReadiumCustomError("lcpError", "LCP failed: ${error.message}")
            }
        }

    private fun licenseInvalid(
        reason: String,
        error: Error,
    ) = FlutterReadiumCustomError("lcpLicenseInvalid", "The license is invalid: ${error.message}", mapOf("reason" to reason))

    private fun licenseStatus(error: LcpError.LicenseStatus): FlutterReadiumCustomError {
        val data =
            when (error) {
                is LcpError.LicenseStatus.Cancelled -> {
                    mapOf("status" to "cancelled", "date" to error.date.toString())
                }

                is LcpError.LicenseStatus.Returned -> {
                    mapOf("status" to "returned", "date" to error.date.toString())
                }

                is LcpError.LicenseStatus.NotStarted -> {
                    mapOf("status" to "notStarted", "start" to error.start.toString())
                }

                is LcpError.LicenseStatus.Expired -> {
                    mapOf("status" to "expired", "end" to error.end.toString())
                }

                is LcpError.LicenseStatus.Revoked -> {
                    mapOf(
                        "status" to "revoked",
                        "date" to error.date.toString(),
                        "devicesCount" to error.devicesCount,
                    )
                }
            }
        return FlutterReadiumCustomError("lcpLicenseStatus", error.message, data)
    }
}
