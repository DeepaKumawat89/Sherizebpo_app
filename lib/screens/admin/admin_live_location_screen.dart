import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class AdminLiveLocationScreen extends StatefulWidget {
  const AdminLiveLocationScreen({super.key, FirebaseFirestore? firestore})
      : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  @override
  State<AdminLiveLocationScreen> createState() => _AdminLiveLocationScreenState();
}

class _AdminLiveLocationScreenState extends State<AdminLiveLocationScreen> {
  FirebaseFirestore get _db => widget._firestore ?? FirebaseFirestore.instance;
  String? _selectedUid;
  DateTime _historyDate = DateTime.now();
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  DateTime? _time(dynamic value) => value is Timestamp ? value.toDate() : null;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Live Employee Locations')),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db.collection('users').snapshots(),
          builder: (context, usersSnap) {
            if (usersSnap.hasError) {
              debugPrint('[LocationDashboard] Employee query failed: ${usersSnap.error}');
              return const Center(child: Text('Unable to load employees.'));
            }
            if (!usersSnap.hasData) return const Center(child: CircularProgressIndicator());
            final employees = {for (final d in usersSnap.data!.docs) d.id: d.data()};
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db.collection('employee_locations').snapshots(),
              builder: (context, locationsSnap) {
                if (locationsSnap.hasError) {
                  debugPrint('[LocationDashboard] Latest locations query failed: ${locationsSnap.error}');
                  return const Center(child: Text('Unable to load locations. Check admin permissions.'));
                }
                if (!locationsSnap.hasData) return const Center(child: CircularProgressIndicator());
                final locations = locationsSnap.data!.docs
                    .where((d) => employees.containsKey(d.id))
                    .toList();
                final active = locations.where((d) => d.data()['tracking'] == true).toList();
                final markers = <Marker>{};
                for (final doc in active) {
                  final data = doc.data();
                  final lat = (data['latitude'] as num?)?.toDouble();
                  final lng = (data['longitude'] as num?)?.toDouble();
                  if (lat == null || lng == null) continue;
                  markers.add(Marker(
                    markerId: MarkerId(doc.id),
                    position: LatLng(lat, lng),
                    infoWindow: InfoWindow(title: _name(employees[doc.id]!)),
                    onTap: () => setState(() => _selectedUid = doc.id),
                  ));
                }
                final first = markers.isEmpty ? const LatLng(20.5937, 78.9629) : markers.first.position;
                debugPrint('[LocationDashboard] Loaded ${active.length} sharing records and ${markers.length} map markers from employee_locations.');
                return Column(children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.42,
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(target: first, zoom: markers.isEmpty ? 4 : 11),
                      markers: markers,
                      myLocationButtonEnabled: false,
                      mapToolbarEnabled: false,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(children: [
                      const Icon(Icons.circle, color: Colors.green, size: 11),
                      const SizedBox(width: 8),
                      Text('${active.length} currently sharing'),
                      const Spacer(),
                      const Text('History kept 30 days', style: TextStyle(fontSize: 12)),
                    ]),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: locations.length,
                      itemBuilder: (context, index) {
                        final doc = locations[index];
                        final data = doc.data();
                        final updated = _time(data['updatedAt']);
                        final tracking = data['tracking'] == true;
                        final fresh = tracking && updated != null && _now.difference(updated) < const Duration(minutes: 2);
                        final selected = _selectedUid == doc.id;
                        return Column(children: [
                          ListTile(
                            selected: selected,
                            leading: Icon(Icons.circle, size: 12, color: fresh ? Colors.green : Colors.grey),
                            title: Text(_name(employees[doc.id]!)),
                            subtitle: Text('${tracking ? (fresh ? 'Live' : 'Sharing · location stale') : 'Not sharing'} · ${updated == null ? 'No fix yet' : _age(updated)}'),
                            trailing: IconButton(
                              tooltip: 'View shift history',
                              icon: const Icon(Icons.history),
                              onPressed: () => setState(() => _selectedUid = selected ? null : doc.id),
                            ),
                            onTap: () => setState(() => _selectedUid = selected ? null : doc.id),
                          ),
                          if (selected) _history(doc.id),
                        ]);
                      },
                    ),
                  ),
                ]);
              },
            );
          },
        ),
      );

  Widget _history(String uid) {
    final date = _historyDate;
    final day = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('employee_location_history').doc('${uid}_$day').collection('points').orderBy('recordedAt', descending: true).limit(100).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return const ListTile(title: Text('Unable to load location history.'));
        if (!snap.hasData) return const LinearProgressIndicator();
        return Padding(
          padding: const EdgeInsets.only(left: 72, right: 16, bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Shift history · ${date.day}/${date.month}/${date.year}', style: Theme.of(context).textTheme.titleSmall)),
              IconButton(
                tooltip: 'Choose history date',
                icon: const Icon(Icons.calendar_today, size: 18),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _historyDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null && mounted) setState(() => _historyDate = picked);
                },
              ),
            ]),
            if (snap.data!.docs.isEmpty) const Text('No location history for this shift date.')
            else ...snap.data!.docs.map((point) {
            final data = point.data();
            final time = _time(data['recordedAt']);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text('${time == null ? '—' : TimeOfDay.fromDateTime(time).format(context)} · ${((data['latitude'] as num?)?.toStringAsFixed(5) ?? '—')}, ${((data['longitude'] as num?)?.toStringAsFixed(5) ?? '—')} · ±${(data['accuracy'] as num?)?.round() ?? '—'} m', style: Theme.of(context).textTheme.bodySmall),
            );
          }),
          ]),
        );
      },
    );
  }

  String _name(Map<String, dynamic> user) => (user['fullName'] ?? user['name'] ?? user['employeeId'] ?? 'Employee').toString();
  String _age(DateTime time) {
    final age = _now.difference(time);
    if (age.inSeconds < 60) return 'updated just now';
    if (age.inMinutes < 60) return 'updated ${age.inMinutes} min ago';
    return 'updated ${age.inHours} hr ago';
  }
}
