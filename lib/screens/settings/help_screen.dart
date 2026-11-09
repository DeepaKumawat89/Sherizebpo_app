import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
 
import '../../core/constants/constants.dart';
import 'widgets/faq_section.dart';
import 'widgets/contact_section.dart';
 
class HelpScreen extends StatefulWidget {
  const HelpScreen({Key? key}) : super(key: key);
 
  @override
  State<HelpScreen> createState() => _HelpScreenState();
}
 
class _HelpScreenState extends State<HelpScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
 
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }
 
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
 
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
 
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Help & Support',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).cardColor,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            LucideIcons.arrowLeft,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Header / Segmented Control Box
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.screenPaddingH,
              AppSizes.xs,
              AppSizes.screenPaddingH,
              AppSizes.base,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : AppColors.textDark.withValues(alpha: 0.06),
                ),
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Theme.of(context).scaffoldBackgroundColor
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : AppColors.textDark.withValues(alpha: 0.05),
                    ),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    splashBorderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    overlayColor:
                        WidgetStateProperty.all<Color>(Colors.transparent),
                    indicator: BoxDecoration(
                      color: isDark ? AppColors.secondaryLight : Colors.white,
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      boxShadow: [
                        if (!isDark)
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                      ],
                    ),
                    labelColor: isDark ? Colors.white : AppColors.textDark,
                    unselectedLabelColor:
                        isDark ? Colors.white54 : AppColors.textMuted,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    padding: const EdgeInsets.all(4),
                    tabs: const [
                      Tab(
                        height: 44,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.helpCircle, size: 16),
                            SizedBox(width: 8),
                            Text('FAQs'),
                          ],
                        ),
                      ),
                      Tab(
                        height: 44,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.messageSquare, size: 16),
                            SizedBox(width: 8),
                            Text('Contact Us'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
 
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                FaqSection(),
                ContactSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}