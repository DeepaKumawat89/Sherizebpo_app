import 'package:flutter/material.dart';

import '../core/constants/constants.dart';

class CustomPopupMenuItem<T> {
  const CustomPopupMenuItem({
    required this.value,
    required this.label,
  });

  final T value;
  final String label;
}

class CustomPopupMenuFormField<T> extends FormField<T> {
  CustomPopupMenuFormField({
    super.key,
    required List<CustomPopupMenuItem<T>> items,
    T? initialValue,
    InputDecoration? decoration,
    TextStyle? style,
    ValueChanged<T?>? onChanged,
    FormFieldValidator<T>? validator,
    bool enabled = true,
    String? hintText,
  }) : super(
          initialValue: initialValue,
          validator: validator,
          enabled: enabled,
          builder: (field) => _CustomPopupMenuFieldBody<T>(
            field: field,
            items: items,
            decoration: decoration ?? const InputDecoration(),
            style: style,
            onChanged: onChanged,
            hintText: hintText,
            isEnabled: enabled,
          ),
        );
}

class _CustomPopupMenuFieldBody<T> extends StatelessWidget {
  const _CustomPopupMenuFieldBody({
    required this.field,
    required this.items,
    required this.decoration,
    required this.style,
    required this.onChanged,
    required this.hintText,
    required this.isEnabled,
  });

  final FormFieldState<T> field;
  final List<CustomPopupMenuItem<T>> items;
  final InputDecoration decoration;
  final TextStyle? style;
  final ValueChanged<T?>? onChanged;
  final String? hintText;
  final bool isEnabled;

  Future<void> _openMenu(BuildContext context) async {
    if (!isEnabled || items.isEmpty) return;

    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenSize = MediaQuery.sizeOf(context);
    final menuWidth =
        size.width.clamp(180.0, screenSize.width - 32.0).toDouble();
    final menuHeight =
        (items.length * 52.0).clamp(52.0, screenSize.height * 0.55).toDouble();
    final top = offset.dy + size.height + AppSizes.xs;
    final menuTop = top + menuHeight <= screenSize.height - AppSizes.base
        ? top
        : (offset.dy - menuHeight - AppSizes.xs)
            .clamp(AppSizes.base, screenSize.height - menuHeight - AppSizes.base)
            .toDouble();
    final bottom = screenSize.height - menuTop;

    final selected = await showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        menuTop,
        screenSize.width - offset.dx - menuWidth,
        bottom,
      ),
      constraints: BoxConstraints(
        minWidth: menuWidth,
        maxWidth: menuWidth,
        maxHeight: menuHeight,
      ),
      elevation: 10,
      color: Theme.of(context).cardColor,
      shadowColor: Theme.of(context).shadowColor.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
        ),
      ),
      items: items
          .map(
            (item) => PopupMenuItem<T>(
              value: item.value,
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.base),
              child: Text(
                item.label,
                overflow: TextOverflow.ellipsis,
                style: style ??
                    Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : AppColors.textDark,
                          fontWeight: FontWeight.w500,
                        ),
              ),
            ),
          )
          .toList(),
    );

    if (selected == null) return;
    field.didChange(selected);
    onChanged?.call(selected);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveDecoration = decoration.copyWith(
      errorText: field.errorText,
      suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
    );
    String? selectedLabel;
    for (final item in items) {
      if (item.value == field.value) {
        selectedLabel = item.label;
        break;
      }
    }

    return Builder(
      builder: (fieldContext) => GestureDetector(
        onTap: isEnabled ? () => _openMenu(fieldContext) : null,
        child: InputDecorator(
          decoration: effectiveDecoration,
          isEmpty: selectedLabel == null,
          isFocused: false,
          child: Text(
            selectedLabel ?? hintText ?? '',
            overflow: TextOverflow.ellipsis,
            style: style ??
                Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: selectedLabel == null
                          ? Theme.of(context).hintColor
                          : Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : AppColors.textDark,
                    ),
          ),
        ),
      ),
    );
  }
}
