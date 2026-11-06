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

    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.screenPaddingH,
            vertical: AppSizes.md,
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => _filterFaqs(val, _selectedCategory),
            style: TextStyle(
              color: isDark ? Colors.white : AppColors.textDark,
              fontSize: 15,
            ),
            decoration: InputDecoration(
              hintText: 'Search for answers...',
              hintStyle: TextStyle(
                color: isDark ? Colors.white54 : AppColors.textPlaceholder,
              ),
              prefixIcon: Icon(
                LucideIcons.search,
                color: isDark ? Colors.white54 : AppColors.textMuted,
                size: 20,
              ),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.md, vertical: AppSizes.md),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                borderSide: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                borderSide: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
        ),

        // Categories Map
        SizedBox(
          height: 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPaddingH),
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final cat = _categories[index];
              final isSelected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: AppSizes.sm),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  backgroundColor: Theme.of(context).cardColor,
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.3)
                        : Theme.of(context).dividerColor.withValues(alpha: 0.1),
                  ),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? (isDark ? AppColors.primaryLight : AppColors.primary)
                        : (isDark ? Colors.white54 : AppColors.textMuted),
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusXl),
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
        const SizedBox(height: AppSizes.md),

        // FAQ List
        Expanded(
          child: _isLoadingFaqs
              ? const Center(child: CircularProgressIndicator())
              : _filteredFaqs.isEmpty
                  ? _buildEmptyState(isDark)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSizes.screenPaddingH,
                        vertical: AppSizes.sm,
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSizes.xl),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : AppColors.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.searchX,
              size: 48,
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
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            'Try searching for different keywords.',
            style: TextStyle(
              color: isDark ? Colors.white54 : AppColors.textMuted,
              fontSize: 14,
            ),
          ),
        ],
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

    return Container(
      margin: const EdgeInsets.only(bottom: AppSizes.md),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: AppColors.textDark.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: AppColors.primary,
          collapsedIconColor: isDark ? Colors.white54 : AppColors.textMuted,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSizes.lg,
            vertical: AppSizes.xs,
          ),
          title: Text(
            faq.question,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
          ),
          childrenPadding: const EdgeInsets.only(
            left: AppSizes.lg,
            right: AppSizes.lg,
            bottom: AppSizes.lg,
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  faq.answer,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : AppColors.textBody,
                    height: 1.6,
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
                          : AppColors.primary.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : AppColors.primary.withValues(alpha: 0.1),
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
                              color: isDark ? AppColors.primaryLight : AppColors.primary,
                            ),
                            const SizedBox(width: AppSizes.sm),
                            Text(
                              'Related Questions',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isDark ? AppColors.primaryLight : AppColors.primary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSizes.sm),
                        ...related.map((r) => Padding(
                              padding: const EdgeInsets.only(top: AppSizes.sm),
                              child: InkWell(
                                onTap: () => onRelatedTap(r.question),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.white38 : AppColors.textPlaceholder,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: AppSizes.sm),
                                    Expanded(
                                      child: Text(
                                        r.question,
                                        style: TextStyle(
                                          color: isDark ? AppColors.info : AppColors.primary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          decoration: TextDecoration.underline,
                                          decorationColor: isDark 
                                              ? AppColors.info.withValues(alpha: 0.3) 
                                              : AppColors.primary.withValues(alpha: 0.3),
                                        ),
                                      ),
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
