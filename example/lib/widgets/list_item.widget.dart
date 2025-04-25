import 'package:flutter/material.dart';

class ListItemWidget extends StatelessWidget {
  const ListItemWidget({
    required this.label,
    required this.child,
    this.fontSize,
    this.isVerticalAlignment = false,
    this.verticalPadding = 5.0,
    this.horizontalPadding = 10.0,
    super.key,
  });
  final String label;
  final Widget child;
  final double? fontSize;
  final bool isVerticalAlignment;
  final double verticalPadding;
  final double horizontalPadding;

  @override
  Widget build(final BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          verticalPadding,
          horizontalPadding,
          verticalPadding,
        ),
        child: isVerticalAlignment
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: fontSize ?? 20),
                  ),
                  child,
                ],
              )
            : Column(
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: fontSize ?? 20),
                  ),
                  child,
                ],
              ),
      );
}
