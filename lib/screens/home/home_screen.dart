import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/theme/colors.dart';
import '../../widgets/common/bottom_nav_bar.dart';
import '../../widgets/common/custom_app_bar.dart';
import 'widgets/method_shortcut_row.dart';
import 'widgets/recent_files_list.dart';
import 'widgets/upload_zone.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _homeNavIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        isRootTab: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 640;

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const UploadZone(),
                      const MethodShortcutRow(),
                      RecentFilesList(compact: compact),
                      SizedBox(height: compact ? 6 : 10),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: _homeNavIndex,
        onTap: (index) => AppRoutes.onBottomNavTap(context, index),
      ),
    );
  }
}
