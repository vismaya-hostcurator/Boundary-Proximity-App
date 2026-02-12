import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';

void main() => runApp(const BoundaryApp());

class BoundaryApp extends StatelessWidget {
  const BoundaryApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const BoundaryHome(),
    );
  }
}

class BoundaryHome extends StatefulWidget {
  const BoundaryHome({super.key});
  @override
  State<BoundaryHome> createState() => _BoundaryHomeState();
}

class _BoundaryStateData {
  late double startLat, startLng, endLat, endLng;

  _BoundaryStateData(String jsonString) {
    final Map<String, dynamic> data = jsonDecode(jsonString);
    final List coordinates = data['features'][0]['geometry']['coordinates'];
    startLng = coordinates[0][0].toDouble();
    startLat = coordinates[0][1].toDouble();
    endLng = coordinates[1][0].toDouble();
    endLat = coordinates[1][1].toDouble();
  }
}

enum ProximityState { safe, near, crossed, initializing }

class _BoundaryHomeState extends State<BoundaryHome> {
  final String geoJson = '''
  {
    "type": "FeatureCollection",
    "features": [
      {
        "type": "Feature",
        "properties": { "name": "Test Boundary" },
        "geometry": {
          "type": "LineString",
          "coordinates": [[76.31645188035051, 10.00531744534041], [76.3165839791409, 10.005364330487788]]
        }
      }
    ]
  }
  '''; 

  late _BoundaryStateData boundary;
  ProximityState _currentState = ProximityState.initializing;
  double _distance = 0.0;
  Position? _currentPos;
  DateTime? _lastStateChangeTime;
  final Duration _debounce = const Duration(milliseconds: 500);
  
  // Logic Thresholds
  static const double YELLOW_START = 50.0;
  static const double RED_START = 10.0;

  @override
  void initState() {
    super.initState();
    boundary = _BoundaryStateData(geoJson);
    _initLocationFlow();
  }

  Future<void> _initLocationFlow() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen((Position position) => _processLocation(position));
  }

  void _processLocation(Position pos) {
    double dist = _calculateDistance(pos.latitude, pos.longitude);
    
    // Side detection (Cross Product)
    double val = (pos.latitude - boundary.startLat) * (boundary.endLng - boundary.startLng) - 
                 (pos.longitude - boundary.startLng) * (boundary.endLat - boundary.startLat);

    ProximityState newState;

    if (dist < RED_START && val < 0) {
      // Logic: Less than 10m AND on the wrong side
      newState = ProximityState.crossed;
    } else if (dist <= YELLOW_START) {
      // Logic: Between 50m and 10m (or < 10m on the safe side)
      newState = ProximityState.near;
    } else {
      // Logic: Greater than 50m
      newState = ProximityState.safe;
    }

    if (newState != _currentState) {
      DateTime now = DateTime.now();
      if (_lastStateChangeTime == null || now.difference(_lastStateChangeTime!) > _debounce) {
        if (newState == ProximityState.near || newState == ProximityState.crossed) {
          Vibration.vibrate(duration: 400); // Trigger vibration for Yellow and Red
        }
        setState(() => _currentState = newState);
        _lastStateChangeTime = now;
      }
    }

    setState(() {
      _currentPos = pos;
      _distance = dist;
    });
  }

  double _calculateDistance(double pLat, double pLng) {
    double x1 = boundary.startLat;
    double y1 = boundary.startLng;
    double x2 = boundary.endLat;
    double y2 = boundary.endLng;
    double dx = x2 - x1;
    double dy = y2 - y1;
    double lengthSq = dx * dx + dy * dy;
    double t = lengthSq == 0 ? 0 : ((pLat - x1) * dx + (pLng - y1) * dy) / lengthSq;
    t = t.clamp(0.0, 1.0);
    return Geolocator.distanceBetween(pLat, pLng, x1 + t * dx, y1 + t * dy);
  }

  Color _getBgColor() {
    switch (_currentState) {
      case ProximityState.crossed: return const Color(0xFFB71C1C); // RED
      case ProximityState.near: return Colors.yellow[700]!;         // YELLOW
      case ProximityState.safe: return const Color(0xFF1B5E20);   // GREEN
      default: return Colors.black;
    }
  }

  String _getLabel() {
    switch (_currentState) {
      case ProximityState.crossed: return "CROSSED (UNSAFE)";
      case ProximityState.near: return "NEAR (WARNING)";
      case ProximityState.safe: return "SAFE";
      default: return "INITIALIZING...";
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine text color based on background (Yellow background needs black text)
    Color contentColor = _currentState == ProximityState.near ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: _getBgColor(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: _currentState == ProximityState.near ? Colors.black.withOpacity(0.1) : Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: contentColor.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    Text(_getLabel(), 
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: contentColor)
                    ),
                    const SizedBox(height: 10),
                    Text("${_distance.toStringAsFixed(2)}m", 
                      style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: contentColor)
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              _infoTile("YOUR LOCATION", "Lat: ${_currentPos?.latitude ?? 0}\nLng: ${_currentPos?.longitude ?? 0}"),
              const SizedBox(height: 15),
              _infoTile("BOUNDARY LINE", "Start: ${boundary.startLat}, ${boundary.startLng}\nEnd: ${boundary.endLat}, ${boundary.endLng}"),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoTile(String title, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _currentState == ProximityState.near ? Colors.black.withOpacity(0.1) : Colors.black26, 
        borderRadius: BorderRadius.circular(10)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: _currentState == ProximityState.near ? Colors.black54 : Colors.white60, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(content, style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: _currentState == ProximityState.near ? Colors.black87 : Colors.white)),
        ],
      ),
    );
  }
}