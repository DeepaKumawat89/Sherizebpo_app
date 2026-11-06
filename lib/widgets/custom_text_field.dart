import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants/constants.dart';

/// Production-grade text field with optional prefix, suffix,
/// label, error text, and input formatters.
class CustomTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final String? label;
  final String? errorText;
  final dynamic prefixIcon;
  final Widget? prefix;
  final Widget? suffixIcon;
  final TextInputType keyboardType;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final TextInputAction textInputAction;
  final FocusNode? focusNode;
  final int? maxLines;

  const CustomTextField({
    Key? key,
    this.controller,
    this.hintText,
    this.labelText,
    this.label,
    this.errorText,
    this.prefixIcon,
    this.prefix,
    this.suffixIcon,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.maxLength,
    this.inputFormatters,
    this.onChanged,
    this.validator,
    this.textInputAction = TextInputAction.done,
    this.focusNode,
    this.maxLines = 1,
  }) : super(key: key);

  String? get _effectiveLabel => label ?? labelText;

  Widget? _getEffectivePrefixIcon(BuildContext context) {
    if (prefixIcon == null) return null;
    if (prefixIcon is Widget) return prefixIcon as Widget;
    if (prefixIcon is IconData) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Icon(
        prefixIcon as IconData, 
        size: 20, 
        color: isDark ? Colors.white38 : AppColors.textMuted
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_effectiveLabel != null) ...[
          Text(
            _effectiveLabel!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isDark ? Colors.white70 : AppColors.textBody,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSizes.sm),
        ],
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          enabled: enabled,
          readOnly: readOnly,
          autofocus: autofocus,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          validator: validator,
          textInputAction: textInputAction,
          focusNode: focusNode,
          maxLines: obscureText ? 1 : maxLines,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isDark ? Colors.white : AppColors.textDark,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: isDark ? Colors.white24 : AppColors.textPlaceholder,
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
            errorText: errorText,
            errorStyle: const TextStyle(
              color: AppColors.error,
              fontSize: 12,
            ),
            prefixIcon: _getEffectivePrefixIcon(context),
            prefix: prefix,
            suffixIcon: suffixIcon,
            counterText: '',
            filled: true,
            fillColor: Theme.of(context).cardColor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSizes.base,
              vertical: AppSizes.base,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              borderSide: const BorderSide(color: AppColors.error, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              borderSide: const BorderSide(color: AppColors.error, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
