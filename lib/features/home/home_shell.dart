import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/models/user_model.dart';
import '../../data/models/user_role.dart';
import '../dashboard/dashboard_screen.dart';
import '../map/map_screen.dart';
import '../nutrition/nutrition_screen.dart';
import '../reports/reports_screen.dart';
import '../personnel/personnel_screen.dart';
import '../profile/profile_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.user,
    required this.onToggleTheme,
    required this.themeMode,
    required this.onToggleLanguage,
    required this.locale,
  });

  final AppUser user;
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;
  final VoidCallback onToggleLanguage;
  final String locale;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  List<_TabDef> _buildTabs() {
    final u = widget.user;
    return [
      _TabDef(
        icon: Icons.dashboard_rounded,
        label: S.navHome,
        screen: DashboardScreen(user: u),
      ),
      _TabDef(
        icon: Icons.map_rounded,
        label: S.navMap,
        screen: MapScreen(user: u),
      ),
      _TabDef(
        icon: Icons.assignment_rounded,
        label: S.navReports,
        screen: ReportsScreen(user: u),
      ),
      _TabDef(
        icon: Icons.restaurant_menu_rounded,
        label: S.navNutrition,
        screen: NutritionScreen(user: u),
      ),
      if (u.role.canManagePersonnel)
        _TabDef(
          icon: Icons.people_rounded,
          label: S.personnelTitle,
          screen: PersonnelScreen(user: u),
        ),
      _TabDef(
        icon: Icons.person_rounded,
        label: S.navProfile,
        screen: ProfileScreen(
          user: u,
          onToggleTheme: widget.onToggleTheme,
          themeMode: widget.themeMode,
          onToggleLanguage: () {
            widget.onToggleLanguage();
            // force home shell rebuild too
            setState(() {});
          },
          locale: widget.locale,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _buildTabs();

    // guard index if tabs shrink (shouldn't happen but defensive)
    if (_currentIndex >= tabs.length) _currentIndex = 0;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: tabs.map((t) => t.screen).toList(),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: PaeColors.primary.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: tabs
              .map((t) => BottomNavigationBarItem(
                    icon: Icon(t.icon),
                    label: t.label,
                  ))
              .toList(),
          elevation: 0,
          backgroundColor: Colors.transparent,
        ),
      ),
    );
  }
}

class _TabDef {
  const _TabDef({
    required this.icon,
    required this.label,
    required this.screen,
  });

  final IconData icon;
  final String label;
  final Widget screen;
}
