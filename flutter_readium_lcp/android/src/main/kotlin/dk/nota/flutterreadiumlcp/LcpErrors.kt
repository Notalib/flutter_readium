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

    /** Like [report], for a failed renew or return call. */
    fun reportLoan(
        result: MethodChannel.Result,
        error: Error,
    ) {
        val custom = mapLoan(error)
        result.error(custom.code, custom.message, custom.data)
    }

    /** The failure of the renew web page callback: the plugin cannot show the page, so the app gets the URL. */
    fun reportRenewWebPage(
        result: MethodChannel.Result,
        url: String,
    ) = result.error("lcpRenewWebPage", "The server renews this loan through a web page.", mapOf("url" to url))

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

    private fun mapLoan(error: Error): FlutterReadiumCustomError =
        when (error) {
            is LcpError.LicenseInteractionNotAvailable -> {
                FlutterReadiumCustomError("lcpLoanNotAvailable", "The license does not offer this loan action.")
            }

            is LcpError.Renew.RenewFailed -> {
                loanFailed("rejected", "The server rejected the renewal.")
            }

            is LcpError.Renew.InvalidRenewalPeriod -> {
                FlutterReadiumCustomError(
                    "lcpRenewPeriod",
                    "The requested end date is not allowed.",
                    listOfNotNull(error.maxRenewDate?.let { "maxRenewDate" to it.toString() }).toMap(),
                )
            }

            is LcpError.Renew.UnexpectedServerError -> {
                loanFailed("server", "The license server failed to renew the loan.")
            }

            is LcpError.Return.ReturnFailed -> {
                loanFailed("rejected", "The server rejected the return.")
            }

            is LcpError.Return.AlreadyReturnedOrExpired -> {
                FlutterReadiumCustomError("lcpAlreadyReturned", "The loan was already returned or has expired.")
            }

            is LcpError.Return.UnexpectedServerError -> {
                loanFailed("server", "The license server failed to return the loan.")
            }

            else -> {
                map(error)
            }
        }

    private fun loanFailed(
        reason: String,
        message: String,
    ) = FlutterReadiumCustomError("lcpLoanFailed", message, mapOf("reason" to reason))

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
