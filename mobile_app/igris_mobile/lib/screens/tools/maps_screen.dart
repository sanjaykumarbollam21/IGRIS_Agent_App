import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:igris_mobile/services/configuration_service.dart';

class MapsScreen extends StatefulWidget {
  const MapsScreen({super.key});

  @override
  State<MapsScreen> createState() => _MapsScreenState();
}

class _MapsScreenState extends State<MapsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // Directions state
  final _originCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  String _travelMode = 'driving';
  bool _loadingDir = false;
  Map<String, dynamic>? _directionResult;

  // Nearby places state
  final _queryCtrl = TextEditingController();
  bool _loadingPlaces = false;
  List<Map<String, dynamic>> _places = [];
  String? _currentLocation;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _detectLocation();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _originCtrl.dispose();
    _destCtrl.dispose();
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _detectLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      setState(() =>
          _currentLocation = '${pos.latitude},${pos.longitude}');
      if (_originCtrl.text.isEmpty) {
        _originCtrl.text = 'My location';
      }
    } catch (_) {}
  }

  Future<String> get _authToken async {
    const secureStorage = FlutterSecureStorage();
    return await secureStorage.read(key: 'auth_token') ?? '';
  }

  String get _apiBase => ConfigurationService().backendUrl;

  // ── Get directions via backend ─────────────────────────────────────────────
  Future<void> _getDirections() async {
    final origin = _originCtrl.text.trim();
    final dest = _destCtrl.text.trim();
    if (origin.isEmpty || dest.isEmpty) {
      _snack('Enter both origin and destination');
      return;
    }
    setState(() { _loadingDir = true; _directionResult = null; });

    try {
      // Open Google Maps directly — most reliable cross-platform approach
      final mapsUrl = _buildMapsUrl(origin, dest, _travelMode);
      setState(() {
        _directionResult = {
          'origin': origin,
          'destination': dest,
          'mode': _travelMode,
          'mapsUrl': mapsUrl,
          'via': 'Google Maps',
        };
        _loadingDir = false;
      });
    } catch (e) {
      setState(() => _loadingDir = false);
      _snack('Error: $e');
    }
  }

  String _buildMapsUrl(String origin, String dest, String mode) {
    final o = Uri.encodeComponent(
        origin == 'My location' && _currentLocation != null
            ? _currentLocation!
            : origin);
    final d = Uri.encodeComponent(dest);
    return 'https://www.google.com/maps/dir/?api=1&origin=$o&destination=$d&travelmode=$mode';
  }

  // ── Search nearby places via AI endpoint ──────────────────────────────────
  Future<void> _searchNearby() async {
    final query = _queryCtrl.text.trim();
    if (query.isEmpty) {
      _snack('Enter a place type to search');
      return;
    }
    setState(() { _loadingPlaces = true; _places = []; });

    try {
      final token = await _authToken;
      final loc = _currentLocation ?? '';
      final resp = await http.post(
        Uri.parse('$_apiBase/tools/web-search'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'query': '$query near me${loc.isNotEmpty ? " at $loc" : ""}',
        }),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        // Build structured place list from search results
        final results = data['results'] as List? ?? [];
        final places = results.take(8).map<Map<String, dynamic>>((r) => {
          'name': r['title'] ?? query,
          'address': r['url'] ?? '',
          'snippet': r['snippet'] ?? '',
          'url': r['url'] ?? '',
        }).toList();
        setState(() { _places = places; _loadingPlaces = false; });
      } else {
        setState(() => _loadingPlaces = false);
        _snack('Search failed (${resp.statusCode})');
      }
    } catch (e) {
      setState(() => _loadingPlaces = false);
      _snack('Search error: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Maps & Navigation'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.directions), text: 'Directions'),
            Tab(icon: Icon(Icons.place), text: 'Nearby'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildDirectionsTab(cs),
          _buildNearbyTab(cs),
        ],
      ),
    );
  }

  // ── Directions Tab ─────────────────────────────────────────────────────────
  Widget _buildDirectionsTab(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Input card
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _originCtrl,
                    decoration: _decor('From', Icons.my_location),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _destCtrl,
                    decoration: _decor('To', Icons.location_on),
                    onSubmitted: (_) => _getDirections(),
                  ),
                  const SizedBox(height: 16),
                  // Mode selector
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _modeBtn('driving', Icons.directions_car, cs),
                      _modeBtn('walking', Icons.directions_walk, cs),
                      _modeBtn('transit', Icons.directions_transit, cs),
                      _modeBtn('bicycling', Icons.directions_bike, cs),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _loadingDir ? null : _getDirections,
                    icon: _loadingDir
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.directions),
                    label: const Text('Get Directions'),
                  ),
                ],
              ),
            ),
          ),

          // Result card
          if (_directionResult != null) ...[
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: cs.primary),
                        const SizedBox(width: 8),
                        Text('Route Ready',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: cs.primary)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _resultRow('From', _directionResult!['origin']),
                    _resultRow('To', _directionResult!['destination']),
                    _resultRow('Mode',
                        _directionResult!['mode'].toString().toUpperCase()),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => launchUrl(
                              Uri.parse(_directionResult!['mapsUrl']),
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(Icons.map),
                            label: const Text('Open in Maps'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            // Swap origin and destination
                            final tmp = _originCtrl.text;
                            _originCtrl.text = _destCtrl.text;
                            _destCtrl.text = tmp;
                          },
                          icon: const Icon(Icons.swap_vert, size: 16),
                          label: const Text('Swap'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Quick destinations
          const SizedBox(height: 16),
          Text('Quick Searches',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              'Hospital', 'Pharmacy', 'ATM', 'Petrol Pump',
              'Restaurant', 'Supermarket', 'Police Station',
            ].map((q) => ActionChip(
                  label: Text(q, style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    _destCtrl.text = q;
                    _tabs.animateTo(1);
                    _queryCtrl.text = q;
                    _searchNearby();
                  },
                )).toList(),
          ),
        ],
      ),
    );
  }

  // ── Nearby Tab ─────────────────────────────────────────────────────────────
  Widget _buildNearbyTab(ColorScheme cs) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryCtrl,
                  decoration: _decor('Search nearby (e.g. "coffee shop")', Icons.search),
                  onSubmitted: (_) => _searchNearby(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _loadingPlaces ? null : _searchNearby,
                child: _loadingPlaces
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.search),
              ),
            ],
          ),
        ),

        // Quick chips
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: ['Restaurants', 'Hospitals', 'ATMs', 'Petrol', 'Hotels',
                'Pharmacy', 'Schools']
                .map((c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(c, style: const TextStyle(fontSize: 12)),
                        onPressed: () {
                          _queryCtrl.text = c;
                          _searchNearby();
                        },
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 8),

        // Results
        Expanded(
          child: _places.isEmpty && !_loadingPlaces
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.explore, size: 64,
                          color: cs.onSurface.withValues(alpha: 0.2)),
                      const SizedBox(height: 12),
                      Text('Search for places nearby',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _places.length,
                  itemBuilder: (_, i) => _buildPlaceTile(_places[i], cs),
                ),
        ),
      ],
    );
  }

  Widget _buildPlaceTile(Map<String, dynamic> p, ColorScheme cs) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(Icons.place, color: cs.primary, size: 20),
        ),
        title: Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(p['snippet'] ?? p['address'] ?? '',
            style: const TextStyle(fontSize: 11), maxLines: 2),
        trailing: IconButton(
          icon: const Icon(Icons.directions, size: 20),
          onPressed: () {
            _destCtrl.text = p['name'] ?? '';
            _tabs.animateTo(0);
            _getDirections();
          },
          tooltip: 'Get directions',
        ),
        onTap: p['url'] != null
            ? () => launchUrl(Uri.parse(p['url']),
                mode: LaunchMode.externalApplication)
            : null,
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _modeBtn(String mode, IconData icon, ColorScheme cs) {
    final selected = _travelMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _travelMode = mode),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon,
            color: selected ? cs.onPrimary : cs.onSurface, size: 22),
      ),
    );
  }

  Widget _resultRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text('$label:',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );

  InputDecoration _decor(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      );
}
