import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:flutter_readium_web/flutter_readium_web.dart';
import 'package:flutter_readium_web/js_publication_channel.dart';

import 'package:web/web.dart' as web;
import 'dart:js_interop' as js_interop;

class ReadiumWebView extends StatefulWidget {
  const ReadiumWebView({
    super.key,
    required this.publicationURL,
    this.currentLocatorString,
  });

  final String publicationURL;
  final String? currentLocatorString;

  @override
  ReadiumWebViewState createState() => ReadiumWebViewState();

  static Function(String)? onLocatorUpdate;
}

class ReadiumWebViewState extends State<ReadiumWebView> {
  @override
  void initState() {
    super.initState();
  }

  @js_interop.JSExport()
  void onLocatorUpdate(final String locatorJsonString) {
    final locatorJson = jsonDecode(locatorJsonString);
    final locator = Locator.fromJson(locatorJson);
    FlutterReadiumWeb.addLocatorUpdate(locator);
  }

  void registerLocatorUpdate() {
    updateLocator = onLocatorUpdate.toJS;
  }

  void createPlatformView(int id, web.HTMLDivElement htmlElement) async {
    try {
      await JsPublicationChannel()
          .openPublication(widget.publicationURL, initialPositionJson: widget.currentLocatorString);
      updateLocator = onLocatorUpdate.toJS;
    } catch (e) {
      // This is a temporary solution to show an error message when opening a publication fails
      // Do we need to have the app send what message it wants to show and make a dialog here? or continue to display it in the html view?
      // Since this is when opening a widget there is nothing expecting a return value so we can't return an error
      final errorElement = web.HTMLDivElement();
      errorElement.textContent = 'Something went wrong opening the publication';
      errorElement.style.fontSize = '24px';
      errorElement.className = 'OpeningReadiumException';
      errorElement.style.margin = '25% auto';
      errorElement.style.textAlign = 'center';

      htmlElement.append(errorElement);

      throw OpeningReadiumException(e.toString(), type: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      tagName: 'div',
      onElementCreated: (element) {
        final wrapperElement = element as web.HTMLDivElement;
        wrapperElement.id = 'wrapper';

        final htmlElement = web.HTMLDivElement();
        htmlElement.id = 'container';
        htmlElement.setAttribute('aria-label', 'Publication');

        wrapperElement.append(htmlElement);

        void mutationCallback(js_interop.JSArray<web.MutationRecord> mutations, web.MutationObserver observer) {
          final container = web.document.getElementById('container');

          if (container != null) {
            observer.disconnect();
            createPlatformView(container.hashCode, htmlElement);
          }
        }

        final htmlObserver = web.MutationObserver(mutationCallback.toJS);

        final htmlBody = web.document.body;

        if (htmlBody != null) {
          htmlObserver.observe(
              htmlBody,
              web.MutationObserverInit(
                childList: true,
                subtree: true,
              ));
        } else {
          throw Exception('Body element not found');
        }
      },
    );
  }
}
