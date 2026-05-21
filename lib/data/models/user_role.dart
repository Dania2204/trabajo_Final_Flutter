import '../../core/l10n/app_strings.dart';

enum UserRole { superAdmin, admin, rector, driver }

extension UserRoleX on UserRole {
  String get label {
    switch (this) {
      case UserRole.superAdmin: return S.roleSuperAdmin;
      case UserRole.admin:      return S.roleAdmin;
      case UserRole.rector:     return S.roleRector;
      case UserRole.driver:     return S.roleDriver;
    }
  }

  String get description {
    switch (this) {
      case UserRole.superAdmin: return S.roleDescSuperAdmin;
      case UserRole.admin:      return S.roleDescAdmin;
      case UserRole.rector:     return S.roleDescRector;
      case UserRole.driver:     return S.roleDescDriver;
    }
  }

  bool get canViewAllReports =>
      this == UserRole.superAdmin || this == UserRole.admin || this == UserRole.rector;

  bool get canManagePersonnel =>
      this == UserRole.superAdmin || this == UserRole.admin || this == UserRole.rector;

  bool get canManageUsers => canManagePersonnel;

  bool get canDeleteUsers => canManageUsers;

  bool get canCreateOrders =>
      this == UserRole.superAdmin || this == UserRole.admin;

  bool get canAddSchoolLocation =>
      this == UserRole.superAdmin || this == UserRole.admin;

  bool get canDriveRoute => this == UserRole.driver;

  bool get canSubmitReport =>
      this == UserRole.rector || this == UserRole.driver;

  List<UserRole> get creatableRoles {
    if (!canManageUsers) return const [];
    return const [UserRole.admin, UserRole.rector, UserRole.driver];
  }

  static UserRole fromString(String v) =>
      UserRole.values.firstWhere((e) => e.name == v,
          orElse: () => UserRole.driver);
}
