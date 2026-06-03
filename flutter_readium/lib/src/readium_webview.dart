import 'dart:convert';
import 'dart:js_interop' as js_interop;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_readium_platform_interface/flutter_readium_platform_interface.dart';
import 'package:web/web.dart' as web;

import 'flutter_readium_web.dart';
import 'js_publication_channel.dart';

class ReadiumWebView extends StatefulWidget {
  const ReadiumWebView({
    required this.publication,
    super.key,
    this.currentLocator,
    this.onTextSelected,
    this.onSelectionAction,
    this.onDecorationInteraction,
  });

  final Publication publication;
  final Locator? currentLocator;
  final void Function(TextSelectionEvent)? onTextSelected;
  final void Function(SelectionActionEvent)? onSelectionAction;
  final void Function(DecorationInteractionEvent)? onDecorationInteraction;

  @override
  ReadiumWebViewState createState() => ReadiumWebViewState();

  static Function(String)? onLocatorUpdate;
}

class ReadiumWebViewState extends State<ReadiumWebView> {
  @override
  void initState() {
    super.initState();
  }

  final _readium = FlutterReadiumPlatform.instance;
  static final _log = ReadiumLog.tag('WebView');

  EPUBPreferences? get _defaultPreferences => _readium.defaultPreferences;

  @js_interop.JSExport()
  void onTextLocatorUpdate(final String locatorJsonString) {
    final locatorJson = jsonDecode(locatorJsonString);
    final locator = Locator.fromJson(locatorJson)!;
    FlutterReadiumWebPlugin.addTextLocatorUpdate(locator);
  }

  @js_interop.JSExport()
  void onReaderStatusChanged(final String statusString) {
    _log.d('Reader status changed: $statusString');
    final status = ReadiumReaderStatus.optFromString(statusString);
    if (status != null) {
      FlutterReadiumWebPlugin.addReaderStatusUpdate(status);
    } else {
      _log.w('Unknown ReadiumReaderStatus: $statusString');
    }
  }

  @js_interop.JSExport()
  void onTextSelectedHandler(final String jsonString) {
    final json = jsonDecode(jsonString);
    final event = TextSelectionEvent.fromJson(json);
    widget.onTextSelected?.call(event);
  }

  @js_interop.JSExport()
  void onSelectionActionHandler(final String jsonString) {
    final json = jsonDecode(jsonString);
    final event = SelectionActionEvent.fromJson(json);
    widget.onSelectionAction?.call(event);
  }

  @js_interop.JSExport()
  void onDecorationInteractionHandler(final String jsonString) {
    final json = jsonDecode(jsonString);
    final event = DecorationInteractionEvent.fromJson(json);
    widget.onDecorationInteraction?.call(event);
  }

  @js_interop.JSExport()
  void onTimebasedPlayerStateHandler(final String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    final state = ReadiumTimebasedState.fromJson(json);
    FlutterReadiumWebPlugin.addTimeBasedStateUpdate(state);
  }

  @js_interop.JSExport()
  void onErrorHandler(final String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    final error = ReadiumError.fromJson(json);
    FlutterReadiumWebPlugin.addErrorEvent(error);
  }

  void registerJSExports() {
    updateTextLocator = onTextLocatorUpdate.toJS;
    updateReaderStatus = onReaderStatusChanged.toJS;
    updateTimebasedPlayerState = onTimebasedPlayerStateHandler.toJS;
    onTextSelectedCallback = onTextSelectedHandler.toJS;
    onSelectionActionCallback = onSelectionActionHandler.toJS;
    onDecorationInteractionCallback = onDecorationInteractionHandler.toJS;
    onErrorCallback = onErrorHandler.toJS;
  }

  void createPlatformView(int id, web.HTMLDivElement htmlElement) async {
    try {
      final publicationUrl = widget.publication.links
          .firstWhereOrNull((final link) => link.href.contains('manifest.json'))
          ?.href;

      if (publicationUrl == null) {
        throw Exception('Publication manifest URL not found');
      }

      final pubId = widget.publication.identifier;
      final preferences = _defaultPreferences?.toJson() ?? <String, dynamic>{};
      final currentLocatorString = widget.currentLocator != null ? json.encode(widget.currentLocator) : null;
      registerJSExports();
      await JsPublicationChannel().openPublication(
        publicationUrl,
        pubId: pubId,
        initialPreferences: json.encode(preferences),
        initialPositionJson: currentLocatorString,
      );
    } catch (e) {
      // This is a temporary solution to show an error message when opening a publication fails
      // Do we need to have the app send what message it wants to show and make a dialog here? or continue to display it in the html view?
      // Since this is when opening a widget there is nothing expecting a return value so we can't return an error
      final errorElement = web.HTMLDivElement()
        ..textContent = 'Something went wrong opening the publication'
        ..style.fontSize = '24px'
        ..className = 'OpeningReadiumException'
        ..style.margin = '25% auto'
        ..style.textAlign = 'center';

      htmlElement.append(errorElement);

      throw OpeningReadiumException(e.toString(), type: null);
    }
  }

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
    tagName: 'div',
    onElementCreated: (element) {
      final wrapperElement = (element as web.HTMLDivElement)..id = 'wrapper';

      final htmlElement = web.HTMLDivElement()
        ..id = 'container'
        ..setAttribute('aria-label', 'Publication');

      wrapperElement.append(htmlElement);

      void mutationCallback(
        js_interop.JSArray<web.MutationRecord> mutations,
        web.MutationObserver observer,
      ) {
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
          web.MutationObserverInit(childList: true, subtree: true),
        );
      } else {
        throw Exception('Body element not found');
      }
    },
  );
}
