// Copyright (c) 2021 Mantano. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.Iridium file.

class LinkPagination {
  LinkPagination(this.firstPageNumber, this.pagesCount);
  final int firstPageNumber;
  final int pagesCount;

  bool containsPage(int page) => firstPageNumber <= page && page < firstPageNumber + pagesCount;

  int computePercent(int page) {
    final nbPageInSpineItem = page - firstPageNumber;
    return nbPageInSpineItem * 100 ~/ pagesCount;
  }

  @override
  String toString() => 'LinkPagination{firstPageNumber: $firstPageNumber, pagesCount: $pagesCount}';
}
