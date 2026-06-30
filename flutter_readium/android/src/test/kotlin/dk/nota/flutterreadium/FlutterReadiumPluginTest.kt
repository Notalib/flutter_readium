package dk.nota.flutterreadium

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertTrue
import org.junit.Ignore
import org.junit.Test

/*
 * This demonstrates a simple unit test of the Kotlin portion of this plugin's implementation.
 *
 * Once you have built the plugin's example app, you can run these tests from the command
 * line by running `./gradlew testDebugUnitTest` in the `example/android/` directory, or
 * you can run them directly from IDEs that support JUnit such as Android Studio.
 */

@Ignore("TODO: flesh out plugin-level method call tests")
internal class FlutterReadiumPluginTest {
    private class CapturingResult : MethodChannel.Result {
        var successValue: Any? = null
        var errorCode: String? = null
        var notImplementedCalled: Boolean = false

        override fun success(result: Any?) {
            successValue = result
        }

        override fun error(
            errorCode: String,
            errorMessage: String?,
            errorDetails: Any?,
        ) {
            this.errorCode = errorCode
        }

        override fun notImplemented() {
            notImplementedCalled = true
        }
    }

    @Test
    fun onMethodCall_returnsNotImplemented() {
        val plugin = FlutterReadiumPlugin()

        val call = MethodCall("getPlatformVersion", null)
        val result = CapturingResult()
        plugin.onMethodCall(call, result)

        assertTrue(result.notImplementedCalled)
    }
}
