
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
 
import '../../../../core/constants/constants.dart';
import '../../../../models/faq_model.dart';
import '../../../../services/support_service.dart';
 
class FaqSection extends StatefulWidget {
  const FaqSection({Key? key}) : super(key: key);
 
  @override
  State<FaqSection> createState() => _FaqSectionState();
}
 
class _FaqSectionState extends State<FaqSection> {
  final TextEditingController _searchController = TextEditingController();
 
  List<FaqModel> _allFaqs = [];
  List<FaqModel> _filteredFaqs = [];
  bool _isLoadingFaqs = true;
  String _selectedCategory = 'All';
 
  final List<String> _categories = [
    'All',
    'General',
    'Tasks',
    'Payments',
    'KYC',
    'Technical'
  ];
 
  @override
  void initState() {
    super.initState();
    _loadFaqs();
  }
 
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
 
  Future<void> _loadFaqs() async {
    setState(() => _isLoadingFaqs = true);
    _allFaqs = await SupportService().getFaqs();
 
    _filteredFaqs = List.from(_allFaqs);
    if (mounted) {
      setState(() => _isLoadingFaqs = false);
    }
  }
 
  void _filterFaqs(String query, String category) {
    setState(() {
      _filteredFaqs = _allFaqs.where((faq) {
        final matchesQuery =
            faq.question.toLowerCase().contains(query.toLowerCase()) ||
                faq.answer.toLowerCase().contains(query.toLowerCase());
        final matchesCategory = category == 'All' || faq.category == category;
        return matchesQuery && matchesCategory;
      }).toList();
    });
  }
 
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = Theme.of(context).dividerColor.withValues(alpha: 0.1);
    final fieldBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : AppColors.textDark.withValues(alpha: 0.08);
 
    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.screenPaddingH,
            AppSizes.md,
            AppSizes.screenPaddingH,
            AppSizes.md,
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => _filterFaqs(val, _selectedCategory),
            cursorColor: AppColors.primary,
            style: TextStyle(
              color: isDark ? Colors.white : AppColors.textDark,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'Search for answers...',
              hintStyle: TextStyle(
                color: isDark ? Colors.white54 : AppColors.textPlaceholder,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Icon(
                LucideIcons.search,
                color: isDark ? Colors.white54 : AppColors.textMuted,
                size: 20,
              ),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.md, vertical: AppSizes.base),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                borderSide: BorderSide(color: fieldBorderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                borderSide: BorderSide(color: fieldBorderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.6),
              ),
            ),
          ),
        ),
 
        // Categories Map
        SizedBox(
          height: 38,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding:
                const EdgeInsets.symmetric(horizontal: AppSizes.screenPaddingH),
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final cat = _categories[index];
              final isSelected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: AppSizes.sm),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  showCheckmark: false,
                  elevation: 0,
                  pressElevation: 0,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                  backgroundColor: Theme.of(context).cardColor,
                  selectedColor: AppColors.primary,
                  side: BorderSide(
                    color: isSelected ? AppColors.primary : fieldBorderColor,
                  ),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : (isDark ? Colors.white70 : AppColors.textBody),
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusRound),
                  ),
                  onSelected: (selected) {
                    setState(() => _selectedCategory = cat);
                    _filterFaqs(_searchController.text, cat);
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSizes.sm),
 
        // FAQ List
        Expanded(
          child: _isLoadingFaqs
              ? const Center(child: CircularProgressIndicator())
              : _filteredFaqs.isEmpty
                  ? _buildEmptyState(isDark)
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSizes.screenPaddingH,
                        AppSizes.sm,
                        AppSizes.screenPaddingH,
                        AppSizes.xxl,
                      ),
                      itemCount: _filteredFaqs.length,
                      itemBuilder: (context, index) {
                        return _FaqItem(
                          faq: _filteredFaqs[index],
                          isDark: isDark,
                          onRelatedTap: (relatedQ) {
                            _searchController.text = relatedQ;
                            _filterFaqs(relatedQ, 'All');
                            setState(() => _selectedCategory = 'All');
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }
 
  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : AppColors.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : AppColors.textDark.withValues(alpha: 0.06),
                ),
              ),
              child: Icon(
                LucideIcons.searchX,
                size: 40,
                color: isDark ? Colors.white38 : AppColors.textPlaceholder,
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            Text(
              'No FAQs found',
              style: TextStyle(
                color: isDark ? Colors.white : AppColors.textDark,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: AppSizes.sm),
            Text(
              'Try searching for different keywords.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white54 : AppColors.textMuted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
 
class _FaqItem extends StatelessWidget {
  final FaqModel faq;
  final bool isDark;
  final Function(String) onRelatedTap;
 
  const _FaqItem({
    required this.faq,
    required this.isDark,
    required this.onRelatedTap,
  });
 
  @override
  Widget build(BuildContext context) {
    final related = SupportService().getRelatedFaqs(faq);
    final accent = isDark ? AppColors.primaryLight : AppColors.primary;
 
    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.textDark.withValues(alpha: 0.06),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: AppColors.textDark.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                )
              ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: AppColors.primary,
          collapsedIconColor: isDark ? Colors.white54 : AppColors.textMuted,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSizes.base,
            vertical: AppSizes.xs,
          ),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            ),
            child: Icon(LucideIcons.helpCircle, size: 18, color: accent),
          ),
          title: Text(
            faq.question,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              height: 1.35,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
          ),
          childrenPadding: const EdgeInsets.only(
            left: AppSizes.base,
            right: AppSizes.base,
            bottom: AppSizes.base,
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : AppColors.textDark.withValues(alpha: 0.06),
                ),
                const SizedBox(height: AppSizes.md),
                Text(
                  faq.answer,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : AppColors.textBody,
                    height: 1.65,
                    fontSize: 14,
                  ),
                ),
                if (related.isNotEmpty) ...[
                  const SizedBox(height: AppSizes.lg),
                  Container(
                    padding: const EdgeInsets.all(AppSizes.md),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : AppColors.primary.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : AppColors.primary.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              LucideIcons.link,
                              size: 14,
                              color: accent,
                            ),
                            const SizedBox(width: AppSizes.sm),
                            Text(
                              'Related Questions',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSizes.xs),
                        ...related.map((r) => InkWell(
                              onTap: () => onRelatedTap(r.question),
                              borderRadius:
                                  BorderRadius.circular(AppSizes.radiusSm),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: AppSizes.sm),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        r.question,
                                        style: TextStyle(
                                          color: isDark
                                              ? AppColors.info
                                              : AppColors.primary,
                                          fontSize: 13.5,
                                          height: 1.35,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: AppSizes.sm),
                                    Icon(
                                      LucideIcons.arrowUpRight,
                                      size: 15,
                                      color: isDark
                                          ? AppColors.info
                                          : AppColors.primary,
                                    ),
                                  ],
                                ),
                              ),
                            )),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
 