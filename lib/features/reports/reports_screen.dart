import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/datasources/database_helper.dart';
import '../../data/models/delivery_model.dart';
import '../../data/models/report_model.dart';
import '../../data/models/user_model.dart';
import '../../data/models/user_role.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.user});
  final AppUser user;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<DeliveryReport> _reports = [];
  List<DeliveryOrder> _myOrders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final canView = widget.user.role.canViewAllReports;
    _tabCtrl = TabController(length: canView ? 2 : 1, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final reports = await DatabaseHelper.instance.getReports();
    final orders = await DatabaseHelper.instance.getOrders();
    setState(() {
      _reports = reports;
      // FIX: El conductor ve los pedidos asignados a él Y los pedidos sin
      // conductor asignado (isOpen). Así siempre hay opciones en el dropdown.
      if (widget.user.role.canViewAllReports) {
        _myOrders = orders;
      } else {
        _myOrders = orders
            .where((o) =>
                o.assignedDriverId == widget.user.id || o.isOpen)
            .toList();
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canView = widget.user.role.canViewAllReports;
    final canSubmit = widget.user.role.canSubmitReport;

    return Scaffold(
      body: Column(
        children: [
          GradientHeader(
            title: S.reportTitle,
            subtitle: S.text(
              'report.total_count',
              '${_reports.length} informes en total',
              '${_reports.length} reports total',
            ),
            height: 110,
            actions: [
              if (canSubmit)
                IconButton(
                  icon: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 28),
                  onPressed: () => _showNewReportSheet(),
                ),
            ],
          ),

          if (canView) ...[
            Container(
              color: PaeColors.gradStart,
              child: TabBar(
                controller: _tabCtrl,
                indicatorColor: PaeColors.accent,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                labelStyle: const TextStyle(
                  fontFamily: PaeTypography.fontBody,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                tabs: [
                  Tab(
                    text: S.text(
                        'report.tab_all', 'Todos los informes', 'All Reports'),
                  ),
                  Tab(
                    text: S.text(
                        'report.tab_mine', 'Mis envíos', 'My Submissions'),
                  ),
                ],
              ),
            ),
          ],

          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: PaeColors.primary))
                : canView
                    ? TabBarView(
                        controller: _tabCtrl,
                        children: [
                          _ReportsList(
                              reports: _reports,
                              currentUserId: widget.user.id!),
                          _ReportsList(
                            reports: _reports
                                .where((r) =>
                                    r.submittedByUserId == widget.user.id)
                                .toList(),
                            currentUserId: widget.user.id!,
                          ),
                        ],
                      )
                    : _ReportsList(
                        reports: _reports
                            .where((r) =>
                                r.submittedByUserId == widget.user.id)
                            .toList(),
                        currentUserId: widget.user.id!,
                      ),
          ),
        ],
      ),
    );
  }

  void _showNewReportSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _NewReportSheet(
        user: widget.user,
        orders: _myOrders,
        onSubmitted: () {
          Navigator.pop(context);
          _load();
        },
      ),
    );
  }
}

// ── Reports list ──────────────────────────────────────────────────────────────

class _ReportsList extends StatelessWidget {
  const _ReportsList(
      {required this.reports, required this.currentUserId});
  final List<DeliveryReport> reports;
  final int currentUserId;

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined,
                size: 64, color: PaeColors.inactive),
            const SizedBox(height: 16),
            Text(S.reportNoReports,
                style: const TextStyle(
                    color: PaeColors.textSecondary, fontSize: 15)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {},
      color: PaeColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: reports.length,
        itemBuilder: (_, i) => _ReportCard(report: reports[i]),
      ),
    );
  }
}

// ── Report Card ───────────────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});
  final DeliveryReport report;

  Color get _condColor {
    switch (report.condition) {
      case FoodCondition.good:
        return PaeColors.success;
      case FoodCondition.fair:
        return PaeColors.warning;
      case FoodCondition.poor:
        return PaeColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, yyyy · h:mm a');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PaeColors.divider),
        boxShadow: [
          BoxShadow(
            color: PaeColors.primary.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: PaeColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.assignment_turned_in_rounded,
                    color: PaeColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(report.schoolName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          fontFamily: PaeTypography.fontDisplay,
                        )),
                    Text(
                      S.text('report.submitted_by_name', 'Por {name}',
                              'By {name}')
                          .replaceAll('{name}', report.submittedByName),
                      style: const TextStyle(
                          color: PaeColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              StatusBadge(
                label: report.condition.label,
                color: _condColor,
              ),
            ],
          ),
          if (report.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(report.notes,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: PaeColors.textSecondary, fontSize: 13)),
          ],
          if (report.photoPaths.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 70,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: report.photoPaths.length,
                itemBuilder: (_, i) => Container(
                  width: 70,
                  height: 70,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: PaeColors.divider),
                    image: DecorationImage(
                      image: FileImage(File(report.photoPaths[i])),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.schedule_rounded,
                  size: 13, color: PaeColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                report.createdAt != null
                    ? fmt.format(report.createdAt!)
                    : S.text('report.unknown_date', 'Fecha desconocida',
                        'Unknown date'),
                style: const TextStyle(
                    color: PaeColors.textSecondary, fontSize: 11),
              ),
              const Spacer(),
              StatusBadge(
                label: report.isSynced
                    ? S.reportSynced
                    : S.reportPendingSync,
                color: report.isSynced
                    ? PaeColors.success
                    : PaeColors.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── New Report Sheet ──────────────────────────────────────────────────────────

class _NewReportSheet extends StatefulWidget {
  const _NewReportSheet({
    required this.user,
    required this.orders,
    required this.onSubmitted,
  });

  final AppUser user;
  final List<DeliveryOrder> orders;
  final VoidCallback onSubmitted;

  @override
  State<_NewReportSheet> createState() => _NewReportSheetState();
}

class _NewReportSheetState extends State<_NewReportSheet> {
  DeliveryOrder? _selectedOrder;
  FoodCondition _condition = FoodCondition.good;
  final _notesCtrl = TextEditingController();
  final List<File> _photos = [];
  final _picker = ImagePicker();
  bool _submitting = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final xfile =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (xfile != null) setState(() => _photos.add(File(xfile.path)));
  }

  Future<void> _pickFromGallery() async {
    final xfile =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xfile != null) setState(() => _photos.add(File(xfile.path)));
  }

  Future<void> _submit() async {
    if (_selectedOrder == null) return;
    setState(() => _submitting = true);
    final report = DeliveryReport(
      orderId: _selectedOrder!.id!,
      schoolName: _selectedOrder!.schoolName,
      submittedByUserId: widget.user.id!,
      submittedByName: widget.user.fullName,
      condition: _condition,
      notes: _notesCtrl.text.trim(),
      photoPaths: _photos.map((f) => f.path).toList(),
      createdAt: DateTime.now(),
      isSynced: false,
    );
    await DatabaseHelper.instance.insertReport(report);
    setState(() => _submitting = false);
    widget.onSubmitted();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: PaeColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(S.reportNew,
                style: const TextStyle(
                  fontFamily: PaeTypography.fontDisplay,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                )),
            const SizedBox(height: 20),

            // ── Order selector ───────────────────────────────────────────────
            // FIX: Si no hay pedidos, muestra aviso en lugar de dropdown vacío
            if (widget.orders.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: PaeColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: PaeColors.warning.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: PaeColors.warning, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        S.text(
                          'report.no_orders_warning',
                          'No tienes pedidos asignados. Pide a un administrador que te asigne uno.',
                          'No orders assigned. Ask an admin to assign you one.',
                        ),
                        style: const TextStyle(
                            fontSize: 13, color: PaeColors.warning),
                      ),
                    ),
                  ],
                ),
              )
            else
              DropdownButtonFormField<DeliveryOrder>(
                value: _selectedOrder,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: S.reportSchool,
                  prefixIcon:
                      const Icon(Icons.local_shipping_rounded),
                ),
                hint: Text(S.text(
                  'report.select_delivery_order',
                  'Selecciona un pedido',
                  'Select delivery order',
                )),
                items: widget.orders
                    .map((o) => DropdownMenuItem(
                          value: o,
                          child: Text(
                            '${o.orderId} — ${o.schoolName}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedOrder = v),
              ),
            const SizedBox(height: 16),

            // ── Condition ────────────────────────────────────────────────────
            Text(S.reportCondition,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  fontFamily: PaeTypography.fontBody,
                  color: PaeColors.textSecondary,
                )),
            const SizedBox(height: 8),
            Row(
              children: FoodCondition.values.map((c) {
                final selected = _condition == c;
                final color = c == FoodCondition.good
                    ? PaeColors.success
                    : c == FoodCondition.fair
                        ? PaeColors.warning
                        : PaeColors.error;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _condition = c),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? color.withOpacity(0.15)
                            : PaeColors.bgLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? color : PaeColors.divider,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      // FIX: usa S. en lugar de string hardcodeado
                      child: Text(
                        c.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color:
                              selected ? color : PaeColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          fontFamily: PaeTypography.fontBody,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ── Notes ────────────────────────────────────────────────────────
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: S.reportNotes,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: Icon(Icons.notes_rounded),
                ),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),

            // ── Photos ───────────────────────────────────────────────────────
            Row(
              children: [
                Text(S.reportPhotos,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: PaeColors.textSecondary,
                      fontFamily: PaeTypography.fontBody,
                    )),
                const Spacer(),
                TextButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.camera_alt_outlined, size: 16),
                  label: Text(
                      S.text('report.camera', 'Cámara', 'Camera')),
                  style: TextButton.styleFrom(
                      foregroundColor: PaeColors.primary),
                ),
                TextButton.icon(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined, size: 16),
                  label: Text(
                      S.text('report.gallery', 'Galería', 'Gallery')),
                  style: TextButton.styleFrom(
                      foregroundColor: PaeColors.primary),
                ),
              ],
            ),
            if (_photos.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 70,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photos.length,
                  itemBuilder: (_, i) => Stack(
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          image: DecorationImage(
                            image: FileImage(_photos[i]),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 10,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _photos.removeAt(i)),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: PaeColors.error,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),

            GradientButton(
              label: S.reportSubmit,
              icon: Icons.send_rounded,
              onPressed: (_selectedOrder == null || _submitting ||
                      widget.orders.isEmpty)
                  ? null
                  : _submit,
              isLoading: _submitting,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}