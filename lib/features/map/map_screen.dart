import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';

import '../../app/theme.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/widgets/shared_widgets.dart';
import '../../data/datasources/database_helper.dart';
import '../../data/models/delivery_model.dart';
import '../../data/models/user_model.dart';
import '../../data/models/user_role.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _defaultCenter = LatLng(4.6400, -74.0900);

  final _mapCtrl = MapController();
  final _locationService = Location();
  final _schoolNameCtrl = TextEditingController();
  final _schoolAddrCtrl = TextEditingController();

  List<SchoolLocation> _schools = [];
  List<DeliveryOrder> _orders = [];
  final List<LatLng> _trackPath = [];

  LatLng _driverPos = _defaultCenter;
  LatLng? _currentLocation;
  LatLng? _pendingPin;
  Timer? _trackTimer;
  StreamSubscription<LocationData>? _locationSub;
  int _routeStep = 0;
  bool _tracking = false;
  bool _showAddSchool = false;
  bool _hasCenteredOnCurrentLocation = false;
  String? _locationStatus;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_initLocation());
  }

  @override
  void dispose() {
    _trackTimer?.cancel();
    _locationSub?.cancel();
    _schoolNameCtrl.dispose();
    _schoolAddrCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final schools = await DatabaseHelper.instance.getSchools();
    final orders = await DatabaseHelper.instance.getOrders();
    if (!mounted) return;

    setState(() {
      _schools = schools;
      _orders = orders;
    });

    if (_currentLocation == null && schools.isNotEmpty) {
      _moveMap(schools.first.latLng, 13.8);
    }
  }

  Future<void> _refreshMapData() async {
    await _load();
    await _initLocation();
  }

  Future<void> _initLocation() async {
    try {
      var serviceEnabled = await _locationService.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _locationService.requestService();
      }

      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _locationStatus = 'Location service is disabled';
        });
        return;
      }

      var permission = await _locationService.hasPermission();
      if (permission == PermissionStatus.denied) {
        permission = await _locationService.requestPermission();
      }

      if (permission != PermissionStatus.granted) {
        if (!mounted) return;
        setState(() {
          _locationStatus = 'Location permission was not granted';
        });
        return;
      }

      final locationData = await _locationService.getLocation();
      _applyCurrentLocation(locationData, moveCamera: true);

      await _locationSub?.cancel();
      _locationSub = _locationService.onLocationChanged.listen(
        (locationData) {
          _applyCurrentLocation(
            locationData,
            moveCamera: !_hasCenteredOnCurrentLocation,
          );
        },
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _locationStatus = 'Unable to keep the location updated';
          });
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationStatus = 'Unable to read current location';
      });
    }
  }

  void _applyCurrentLocation(
    LocationData locationData, {
    bool moveCamera = false,
  }) {
    final latitude = locationData.latitude;
    final longitude = locationData.longitude;
    if (latitude == null || longitude == null || !mounted) return;

    final point = LatLng(latitude, longitude);

    setState(() {
      _currentLocation = point;
      _locationStatus = null;
      if (!_tracking) {
        _driverPos = point;
      }
    });

    if (moveCamera || !_hasCenteredOnCurrentLocation) {
      _hasCenteredOnCurrentLocation = true;
      _moveMap(point, 15.2);
    }
  }

  void _moveMap(LatLng target, double zoom) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapCtrl.move(target, zoom);
    });
  }

  Future<void> _goToMyLocation() async {
    if (_currentLocation == null) {
      await _initLocation();
    }

    final point = _currentLocation;
    if (point == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_locationStatus ?? 'Current location is unavailable'),
        ),
      );
      return;
    }

    if (_showAddSchool && _pendingPin == null) {
      setState(() {
        _pendingPin = point;
      });
    }

    _moveMap(point, 15.2);
  }

  void _onMapTap(TapPosition _, LatLng point) {
    if (_showAddSchool) {
      setState(() {
        _pendingPin = point;
      });
    }
  }

  Future<void> _saveSchool() async {
    if (_pendingPin == null || _schoolNameCtrl.text.trim().isEmpty) return;

    final school = SchoolLocation(
      name: _schoolNameCtrl.text.trim(),
      address: _schoolAddrCtrl.text.trim(),
      latitude: _pendingPin!.latitude,
      longitude: _pendingPin!.longitude,
      addedByUserId: widget.user.id!,
    );

    await DatabaseHelper.instance.insertSchool(school);
    _schoolNameCtrl.clear();
    _schoolAddrCtrl.clear();

    if (!mounted) return;

    setState(() {
      _showAddSchool = false;
      _pendingPin = null;
    });

    await _load();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          S.text(
            'map.school_location_saved',
            'Ubicacion de escuela guardada',
            'School location saved',
          ),
        ),
      ),
    );
  }

  Future<void> _createOrder(SchoolLocation school) async {
    final pickup = _currentLocation ?? _driverPos;
    final order = DeliveryOrder(
      schoolId: school.id!,
      schoolName: school.name,
      schoolLat: school.latitude,
      schoolLng: school.longitude,
      pickupLat: pickup.latitude,
      pickupLng: pickup.longitude,
      createdAt: DateTime.now(),
    );

    await DatabaseHelper.instance.insertOrder(order);
    await _load();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          S
              .text(
                'map.order_created_for',
                'Pedido creado para {school}',
                'Order created for {school}',
              )
              .replaceAll('{school}', school.name),
        ),
      ),
    );
  }

  Future<void> _claimOrder(DeliveryOrder order) async {
    await DatabaseHelper.instance.updateOrderStatus(
      order.id!,
      DeliveryStatus.assigned,
      driverId: widget.user.id,
      driverName: widget.user.fullName,
    );
    await _load();
  }

  void _startRoute(DeliveryOrder order) {
    _trackTimer?.cancel();

    final start = _currentLocation ?? order.pickupLatLng;
    final destination = order.schoolLatLng;
    const steps = 20;

    setState(() {
      _tracking = true;
      _routeStep = 0;
      _driverPos = start;
      _trackPath
        ..clear()
        ..add(start);
    });

    unawaited(
      DatabaseHelper.instance.updateOrderStatus(
        order.id!,
        DeliveryStatus.enRoute,
      ),
    );

    _trackTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_routeStep >= steps) {
        timer.cancel();

        await DatabaseHelper.instance.updateOrderStatus(
          order.id!,
          DeliveryStatus.delivered,
        );
        await _load();

        if (!mounted) return;

        setState(() {
          _tracking = false;
          if (_currentLocation != null) {
            _driverPos = _currentLocation!;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              S.text(
                'map.delivery_completed',
                'Entrega completada',
                'Delivery completed',
              ),
            ),
          ),
        );
        return;
      }

      final progress = (_routeStep + 1) / steps;
      final lat =
          start.latitude + (destination.latitude - start.latitude) * progress;
      final lng =
          start.longitude +
          (destination.longitude - start.longitude) * progress;
      final newPos = LatLng(lat, lng);

      await DatabaseHelper.instance.insertTrackingPoint(
        orderId: order.id!,
        driverId: widget.user.id!,
        lat: lat,
        lng: lng,
      );

      if (!mounted) return;

      setState(() {
        _routeStep++;
        _driverPos = newPos;
        _trackPath.add(newPos);
      });

      _moveMap(newPos, 14.5);
    });
  }

  void _stopRoute() {
    _trackTimer?.cancel();
    setState(() {
      _tracking = false;
      if (_currentLocation != null) {
        _driverPos = _currentLocation!;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final isDriver = user.role.canDriveRoute;
    final isRector = user.role.canAddSchoolLocation;
    final canViewAll = user.role.canViewAllReports;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeOrders = _orders
        .where((o) => o.status != DeliveryStatus.delivered)
        .length;

    return Scaffold(
      body: Stack(
        children: [
          ColorFiltered(
            colorFilter: isDark
                ? const ColorFilter.matrix(<double>[
                    -0.85,
                    0,
                    0,
                    0,
                    255,
                    0,
                    -0.85,
                    0,
                    0,
                    255,
                    0,
                    0,
                    -0.85,
                    0,
                    255,
                    0,
                    0,
                    0,
                    1,
                    0,
                  ])
                : const ColorFilter.matrix(<double>[
                    1,
                    0,
                    0,
                    0,
                    0,
                    0,
                    1,
                    0,
                    0,
                    0,
                    0,
                    0,
                    1,
                    0,
                    0,
                    0,
                    0,
                    0,
                    1,
                    0,
                  ]),
            child: FlutterMap(
              key: ValueKey(isDark),
              mapController: _mapCtrl,
              options: MapOptions(
                initialCenter: _defaultCenter,
                initialZoom: 13.5,
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.paego.app',
                ),
                MarkerLayer(
                  markers: [
                    ..._schools.map(
                      (school) => Marker(
                        point: school.latLng,
                        width: 46,
                        height: 56,
                        child: GestureDetector(
                          onTap: () => _showSchoolSheet(school),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: PaeColors.primary,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: PaeColors.primary.withOpacity(0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.school_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const Icon(
                                Icons.arrow_drop_down_rounded,
                                color: PaeColors.primary,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_currentLocation != null && !isDriver)
                      Marker(
                        point: _currentLocation!,
                        width: 48,
                        height: 48,
                        child: Container(
                          decoration: BoxDecoration(
                            color: PaeColors.secondary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.18),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.my_location_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    if (isDriver || _tracking)
                      Marker(
                        point: _driverPos,
                        width: 50,
                        height: 50,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [PaeColors.gradStart, PaeColors.accent],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: PaeColors.primary.withOpacity(0.5),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.local_shipping_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    if (_pendingPin != null)
                      Marker(
                        point: _pendingPin!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_pin,
                          color: PaeColors.error,
                          size: 40,
                        ),
                      ),
                  ],
                ),
                if (_trackPath.length > 1)
                  PolylineLayer(
                    polylines: [
                      Polyline<Object>(
                        points: _trackPath,
                        strokeWidth: 5,
                        color: PaeColors.accent,
                      ),
                    ],
                  ),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('(c) OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GradientHeader(
              title: S.mapTitle,
              subtitle:
                  '${_schools.length} schools / $activeOrders active orders',
              actions: [
                IconButton(
                  icon: const Icon(
                    Icons.my_location_rounded,
                    color: Colors.white,
                  ),
                  onPressed: _goToMyLocation,
                  tooltip: S.mapMyLocation,
                ),
                if (isRector)
                  IconButton(
                    icon: Icon(
                      _showAddSchool
                          ? Icons.close
                          : Icons.add_location_alt_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        _showAddSchool = !_showAddSchool;
                        _pendingPin = null;
                      });
                    },
                    tooltip: S.mapAddSchool,
                  ),
                if (canViewAll || isDriver)
                  IconButton(
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                    ),
                    onPressed: _refreshMapData,
                  ),
              ],
            ),
          ),
          if (_locationStatus != null && !_showAddSchool)
            Positioned(
              top: 110,
              left: 20,
              right: 20,
              child: _MapBanner(
                icon: Icons.gps_off_rounded,
                message: _locationStatus!,
              ),
            ),
          if (_showAddSchool)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: _AddSchoolPanel(
                nameCtrl: _schoolNameCtrl,
                addrCtrl: _schoolAddrCtrl,
                hasPendingPin: _pendingPin != null,
                onSave: _saveSchool,
                onCancel: () {
                  setState(() {
                    _showAddSchool = false;
                    _pendingPin = null;
                  });
                },
              ),
            ),
          // ── Panel del conductor ────────────────────────────────────────
          if (isDriver && !_showAddSchool)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: _DriverOrderPanel(
                orders: _orders,
                user: widget.user,
                tracking: _tracking,
                onClaim: _claimOrder,
                onStart: _startRoute,
                onStop: _stopRoute,
              ),
            ),
          // ── Panel de administración de pedidos (admin/superAdmin) ──────
          if (canViewAll && !_showAddSchool && !isDriver)
            Positioned(
              bottom: 20,
              left: 16,
              right: 16,
              child: _AdminOrdersPanel(
                orders: _orders,
                onRefresh: _refreshMapData,
              ),
            ),
          if (_showAddSchool && _pendingPin == null)
            Positioned(
              top: 110,
              left: 20,
              right: 20,
              child: _MapBanner(
                icon: Icons.touch_app_rounded,
                message: S.mapSelectOnMap,
              ),
            ),
        ],
      ),
    );
  }

  void _showSchoolSheet(SchoolLocation school) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: PaeColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: PaeColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        school.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          fontFamily: PaeTypography.fontDisplay,
                        ),
                      ),
                      Text(
                        school.address,
                        style: const TextStyle(
                          color: PaeColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (widget.user.role.canCreateOrders)
              GradientButton(
                label: S.text(
                  'map.create_delivery_order',
                  'Crear pedido de entrega',
                  'Create delivery order',
                ),
                icon: Icons.add_road_rounded,
                onPressed: () {
                  Navigator.pop(context);
                  unawaited(_createOrder(school));
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _MapBanner extends StatelessWidget {
  const _MapBanner({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: PaeColors.secondary,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: PaeTypography.fontBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddSchoolPanel extends StatelessWidget {
  const _AddSchoolPanel({
    required this.nameCtrl,
    required this.addrCtrl,
    required this.hasPendingPin,
    required this.onSave,
    required this.onCancel,
  });

  final TextEditingController nameCtrl;
  final TextEditingController addrCtrl;
  final bool hasPendingPin;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final textPrimary = isDark ? Colors.white : PaeColors.textPrimary;
    final textSecondary = isDark
        ? Colors.white.withOpacity(0.65)
        : PaeColors.textSecondary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : PaeColors.divider,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                S.mapAddSchool,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  fontFamily: PaeTypography.fontDisplay,
                  color: textPrimary,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: textSecondary),
                onPressed: onCancel,
              ),
            ],
          ),
          if (hasPendingPin) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: PaeColors.success,
                  size: 16,
                ),
                SizedBox(width: 6),
                Text(
                  'Pin placed on map',
                  style: TextStyle(
                    color: PaeColors.success,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: 14),
          TextField(
            controller: nameCtrl,
            decoration: InputDecoration(
              labelText: S.mapSchoolName,
              prefixIcon: const Icon(Icons.school_outlined),
            ),
          ),
          SizedBox(height: 12),
          TextField(
            controller: addrCtrl,
            decoration: InputDecoration(
              labelText: S.mapSchoolAddress,
              prefixIcon: const Icon(Icons.location_on_outlined),
            ),
          ),
          SizedBox(height: 16),
          GradientButton(
            label: S.mapSaveLocation,
            icon: Icons.save_rounded,
            onPressed: hasPendingPin ? onSave : null,
          ),
        ],
      ),
    );
  }
}

class _DriverOrderPanel extends StatelessWidget {
  const _DriverOrderPanel({
    required this.orders,
    required this.user,
    required this.tracking,
    required this.onClaim,
    required this.onStart,
    required this.onStop,
  });

  final List<DeliveryOrder> orders;
  final AppUser user;
  final bool tracking;
  final void Function(DeliveryOrder) onClaim;
  final void Function(DeliveryOrder) onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final textPrimary = isDark ? Colors.white : PaeColors.textPrimary;
    final textSecondary = isDark
        ? Colors.white.withOpacity(0.65)
        : PaeColors.textSecondary;

    final myOrder = orders
        .where(
          (o) =>
              o.assignedDriverId == user.id &&
              o.status != DeliveryStatus.delivered,
        )
        .firstOrNull;
    final available = orders
        .where((o) => o.isOpen && o.status == DeliveryStatus.pending)
        .toList();

    if (myOrder == null && available.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.08) : PaeColors.divider,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 12),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, color: textSecondary),
            const SizedBox(width: 8),
            Text(S.orderNoOrders, style: TextStyle(color: textSecondary)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : PaeColors.divider,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (myOrder != null) ...[
            Text(
              S.orderMyActive,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                fontFamily: PaeTypography.fontDisplay,
              ).copyWith(color: textPrimary),
            ),
            const SizedBox(height: 10),
            _OrderCard(order: myOrder),
            const SizedBox(height: 12),
            if (tracking)
              OutlinedButton.icon(
                onPressed: onStop,
                icon: const Icon(
                  Icons.stop_circle_outlined,
                  color: PaeColors.error,
                ),
                label: Text(
                  S.mapStopRoute,
                  style: TextStyle(color: PaeColors.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: PaeColors.error),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              )
            else if (myOrder.status == DeliveryStatus.assigned)
              GradientButton(
                label: S.mapStartRoute,
                icon: Icons.play_circle_fill_rounded,
                onPressed: () => onStart(myOrder),
                height: 48,
              ),
          ] else ...[
            Text(
              S.orderAvailable,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                fontFamily: PaeTypography.fontDisplay,
              ).copyWith(color: textPrimary),
            ),
            const SizedBox(height: 10),
            ...available
                .take(3)
                .map(
                  (order) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _AvailableOrderRow(
                      order: order,
                      onClaim: () => onClaim(order),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark
        ? Colors.white.withOpacity(0.65)
        : PaeColors.textSecondary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? PaeColors.cardDark : PaeColors.bgLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : PaeColors.divider,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.school_rounded, color: PaeColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.orderId,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: PaeColors.primary,
                  ),
                ),
                Text(
                  order.schoolName,
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
              ],
            ),
          ),
          StatusBadge(
            label: order.status.label,
            color: order.status == DeliveryStatus.enRoute
                ? PaeColors.statusEnRoute
                : PaeColors.statusAssigned,
          ),
        ],
      ),
    );
  }
}

class _AvailableOrderRow extends StatelessWidget {
  const _AvailableOrderRow({required this.order, required this.onClaim});

  final DeliveryOrder order;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? PaeColors.cardDark : PaeColors.bgLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : PaeColors.divider,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.local_shipping_rounded,
            color: PaeColors.primary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${order.orderId} - ${order.schoolName}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: onClaim,
            style: TextButton.styleFrom(
              foregroundColor: PaeColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
            ),
            child: Text(
              S.orderClaimButton,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Admin Orders Panel ────────────────────────────────────────────────────────

class _AdminOrdersPanel extends StatelessWidget {
  const _AdminOrdersPanel({required this.orders, required this.onRefresh});

  final List<DeliveryOrder> orders;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final textPrimary = isDark ? Colors.white : PaeColors.textPrimary;
    final textSecondary = isDark
        ? Colors.white.withOpacity(0.65)
        : PaeColors.textSecondary;
    final pending = orders
        .where((o) => o.status == DeliveryStatus.pending)
        .length;
    final enRoute = orders
        .where((o) => o.status == DeliveryStatus.enRoute)
        .length;
    final assigned = orders
        .where((o) => o.status == DeliveryStatus.assigned)
        .length;
    final recentOrders = orders
        .where((o) => o.status != DeliveryStatus.delivered)
        .take(3)
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : PaeColors.divider,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.local_shipping_rounded,
                color: PaeColors.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Panel de Pedidos',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  fontFamily: PaeTypography.fontDisplay,
                  color: textPrimary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onRefresh,
                child: Icon(
                  Icons.refresh_rounded,
                  color: textSecondary,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Status summary row
          Row(
            children: [
              _StatusPill(
                label: S.orderStatusPending,
                count: pending,
                color: PaeColors.warning,
              ),
              const SizedBox(width: 8),
              _StatusPill(
                label: S.orderStatusAssigned,
                count: assigned,
                color: PaeColors.info,
              ),
              const SizedBox(width: 8),
              _StatusPill(
                label: S.orderStatusEnRoute,
                count: enRoute,
                color: PaeColors.success,
              ),
            ],
          ),
          if (recentOrders.isNotEmpty) ...[
            const SizedBox(height: 10),
            Divider(
              height: 1,
              color: isDark ? Colors.white12 : PaeColors.divider,
            ),
            const SizedBox(height: 8),
            Text(
              S.text('map.active_orders', 'Pedidos activos', 'Active orders'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            ...recentOrders.map(
              (o) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.school_rounded,
                      color: PaeColors.primary,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${o.orderId} — ${o.schoolName}',
                        style: TextStyle(fontSize: 12, color: textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(o.status).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        o.status.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _statusColor(o.status),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              S.text(
                'map.no_active_orders_hint',
                'No hay pedidos activos. Toca una escuela en el mapa para crear un pedido.',
                'No active orders. Tap a school on the map to create an order.',
              ),
              style: TextStyle(fontSize: 12, color: textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(DeliveryStatus s) {
    switch (s) {
      case DeliveryStatus.pending:
        return PaeColors.warning;
      case DeliveryStatus.assigned:
        return PaeColors.info;
      case DeliveryStatus.enRoute:
        return PaeColors.success;
      case DeliveryStatus.delivered:
        return PaeColors.textSecondary;
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: color,
                fontFamily: PaeTypography.fontDisplay,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
