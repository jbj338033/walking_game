import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '걷기 게임',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const WalkingGameScreen(),
    );
  }
}

class WalkingGameScreen extends StatefulWidget {
  const WalkingGameScreen({Key? key}) : super(key: key);

  @override
  _WalkingGameScreenState createState() => _WalkingGameScreenState();
}

class _WalkingGameScreenState extends State<WalkingGameScreen> {
  Position? _currentPosition;
  double _distanceWalked = 0.0;
  int _points = 0;
  bool _isTracking = false;
  Position? _lastPosition;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadPoints();
  }

  Future<void> _loadPoints() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _points = prefs.getInt('points') ?? 0;
    });
  }

  Future<void> _savePoints() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('points', _points);
  }

  Future<void> _checkPermissions() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      print("Error getting location: $e");
    }
  }

  void _startTracking() {
    setState(() {
      _isTracking = true;
    });

    // 위치 추적 시작
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // 5미터마다 업데이트
      ),
    ).listen((Position position) {
      if (_lastPosition != null) {
        double distance = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );

        setState(() {
          _distanceWalked += distance;
          // 100미터마다 10포인트 획득
          if (_distanceWalked >= 100) {
            _points += 10;
            _distanceWalked = 0;
            _savePoints();
          }
        });
      }
      _lastPosition = position;
    });
  }

  void _stopTracking() {
    setState(() {
      _isTracking = false;
      _lastPosition = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('걷기 게임'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '포인트: $_points',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Text(
              '이동 거리: ${_distanceWalked.toStringAsFixed(2)}m',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            if (_currentPosition != null)
              Text(
                '현재 위치:\n위도: ${_currentPosition!.latitude}\n경도: ${_currentPosition!.longitude}',
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _isTracking ? _stopTracking : _startTracking,
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
              child: Text(_isTracking ? '중지' : '시작'),
            ),
          ],
        ),
      ),
    );
  }
}
