// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

import '../link.dart';
import '../publication.dart';

extension PublicationLists on Publication {
  /// Provides navigation to positions in the Publication content that correspond to the locations of
  /// page boundaries present in a print source being represented by this EPUB Publication.
  List<Link> get pageList => collectionLinks('pageList');

  /// Returns [pageList] if available, or generates a page list from [metadata.numberOfPages]
  /// for PDFs without an embedded page list.
  List<Link> get pageListOrGenerated {
    final existing = pageList;
    if (existing.isNotEmpty) return existing;
    if (!conformsToReadiumPDF) return [];
    // For PDFs without an embedded page list, we generate one based on the total number of pages in the PDF.
    final totalPages = metadata.numberOfPages ?? 0;
    if (totalPages == 0) return [];
    final basePath = readingOrder.firstOrNull?.href.split('#').first ?? '';
    return List.generate(totalPages, (i) {
      final page = i + 1;
      // TODO: Localization of "Page x" title.
      return Link(href: '$basePath#page=$page', title: 'Page $page');
    });
  }

  /// Identifies fundamental structural components of the publication in order to enable Reading
  /// Systems to provide the User efficient access to them.
  List<Link> get landmarks => collectionLinks('landmarks');

  List<Link> get listOfAudioClips => collectionLinks('loa');
  List<Link> get listOfIllustrations => collectionLinks('loi');
  List<Link> get listOfTables => collectionLinks('lot');
  List<Link> get listOfVideoClips => collectionLinks('lov');
}
