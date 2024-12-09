import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:pedometer/pedometer.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart' hide Marker;
import 'dart:async';
import 'dart:math';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '걷기 게임',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const WalkingGameScreen(),
    );
  }
}

class WalkingGameScreen extends StatefulWidget {
  const WalkingGameScreen({super.key});

  @override
  State<WalkingGameScreen> createState() => _WalkingGameScreenState();
}

class _WalkingGameScreenState extends State<WalkingGameScreen>
    with SingleTickerProviderStateMixin {
  // Controllers
  fmap.MapController? _mapController;
  TabController? _tabController;
  StreamSubscription<Position>? _positionStream;
  Timer? _simulatorTimer;

  // State variables
  Position? _currentPosition;
  double _distanceWalked = 0.0;
  int _points = 0;
  int _steps = 0;
  int _level = 1;
  bool _isTracking = false;
  bool _isSimulator = false;
  DateTime? _startTime;
  final List<LatLng> _walkingPath = [];

  // Game variables
  final Map<int, int> _levelThresholds = {
    1: 100,
    2: 300,
    3: 600,
    4: 1000,
    5: 1500,
  };

  final List<Achievement> _achievements = [
    Achievement('첫 걸음', '게임 시작하기', 10),
    Achievement('초보 워커', '1km 걷기', 50),
    Achievement('열정 워커', '5km 걷기', 100),
    Achievement('마라토너', '10km 걷기', 200),
  ];

  final List<Achievement> _unlockedAchievements = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _mapController = fmap.MapController();
    _loadSavedData();
    _checkIfSimulator();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.location.request();
    await Permission.activityRecognition.request();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _points = prefs.getInt('points') ?? 0;
      _steps = prefs.getInt('steps') ?? 0;
      _level = prefs.getInt('level') ?? 1;
      _unlockedAchievements.addAll((prefs.getStringList('achievements') ?? [])
          .map((e) => Achievement.fromString(e)));
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('points', _points);
    await prefs.setInt('steps', _steps);
    await prefs.setInt('level', _level);
    await prefs.setStringList('achievements',
        _unlockedAchievements.map((e) => e.toString()).toList());
  }

  Future<void> _checkIfSimulator() async {
    bool isSimulator = !await Geolocator.isLocationServiceEnabled();
    setState(() {
      _isSimulator = isSimulator;
    });
  }

  void _startTracking() {
    setState(() {
      _isTracking = true;
      _startTime = DateTime.now();
      _walkingPath.clear();
    });

    if (_isSimulator) {
      _startSimulation();
    } else {
      _startRealTracking();
    }
  }

  void _startRealTracking() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      _updatePosition(position);
    });

    Pedometer.stepCountStream.listen((StepCount event) {
      setState(() {
        _steps = event.steps;
        _saveData();
      });
    });
  }

  void _startSimulation() {
    final random = Random();
    LatLng lastPosition = const LatLng(37.5665, 126.9780);

    _simulatorTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final newLat =
          lastPosition.latitude + (random.nextDouble() - 0.5) * 0.0001;
      final newLng =
          lastPosition.longitude + (random.nextDouble() - 0.5) * 0.0001;
      final newPosition = Position(
        latitude: newLat,
        longitude: newLng,
        accuracy: 0,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        timestamp: DateTime.now(),
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );

      _updatePosition(newPosition);
      lastPosition = LatLng(newLat, newLng);

      setState(() {
        _steps += 13;
        _saveData();
      });
    });
  }

  void _updatePosition(Position position) {
    setState(() {
      if (_currentPosition != null) {
        final distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          position.latitude,
          position.longitude,
        );

        _distanceWalked += distance;
        _updateGameProgress(distance);
      }

      _currentPosition = position;
      final latLng = LatLng(position.latitude, position.longitude);
      _walkingPath.add(latLng);
      _mapController?.move(latLng, _mapController?.camera.zoom ?? 15);
    });
  }

  void _updateGameProgress(double distance) {
    if (_distanceWalked >= 100) {
      setState(() {
        _points += 10;
        _distanceWalked = 0;
      });
      _checkAchievements();
      _checkLevelUp();
      _saveData();
    }
  }

  void _checkLevelUp() {
    if (_levelThresholds.containsKey(_level)) {
      if (_points >= _levelThresholds[_level]!) {
        setState(() {
          _level++;
        });
        _showLevelUpDialog();
      }
    }
  }

  void _showLevelUpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🎉 레벨 업!'),
        content: Text('축하합니다! 레벨 $_level 달성!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _stopTracking() {
    setState(() {
      _isTracking = false;
    });
    _positionStream?.cancel();
    _simulatorTimer?.cancel();
    _showWorkoutSummary();
  }

  void _checkAchievements() {
    final totalDistance = _calculateTotalDistance(_walkingPath);

    for (final achievement in _achievements) {
      if (!_unlockedAchievements.contains(achievement)) {
        if ((achievement.title == '첫 걸음') ||
            (achievement.title == '초보 워커' && totalDistance >= 1) ||
            (achievement.title == '열정 워커' && totalDistance >= 5) ||
            (achievement.title == '마라토너' && totalDistance >= 10)) {
          _unlockAchievement(achievement);
        }
      }
    }
  }

  void _unlockAchievement(Achievement achievement) {
    setState(() {
      _unlockedAchievements.add(achievement);
      _points += achievement.points;
    });

    _showAchievementDialog(achievement);
  }

  void _showAchievementDialog(Achievement achievement) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🏆 업적 달성!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events, size: 50, color: Colors.amber),
            const SizedBox(height: 16),
            Text(achievement.title),
            Text(achievement.description),
            Text('+${achievement.points} 포인트'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _showWorkoutSummary() {
    if (_startTime == null) return;

    final duration = DateTime.now().difference(_startTime!);
    final distance =
        _walkingPath.isEmpty ? 0.0 : _calculateTotalDistance(_walkingPath);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('운동 요약'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('운동 시간: ${_formatDuration(duration)}'),
            Text('이동 거리: ${distance.toStringAsFixed(2)}km'),
            Text('획득 포인트: $_points'),
            Text('걸음 수: $_steps'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  double _calculateTotalDistance(List<LatLng> path) {
    double totalDistance = 0;
    for (int i = 0; i < path.length - 1; i++) {
      totalDistance += Geolocator.distanceBetween(
        path[i].latitude,
        path[i].longitude,
        path[i + 1].latitude,
        path[i + 1].longitude,
      );
    }
    return totalDistance / 1000;
  }

  String _formatDuration(Duration duration) {
    return '${duration.inHours}시간 ${duration.inMinutes.remainder(60)}분';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('걷기 게임'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.map), text: '지도'),
            Tab(icon: Icon(Icons.analytics), text: '통계'),
            Tab(icon: Icon(Icons.emoji_events), text: '업적'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMapTab(),
          _buildStatsTab(),
          _buildAchievementsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isTracking ? _stopTracking : _startTracking,
        label: Text(_isTracking ? '중지' : '시작'),
        icon: Icon(_isTracking ? Icons.stop : Icons.play_arrow),
      ),
    );
  }

  Widget _buildMapTab() {
    return Stack(
      children: [
        fmap.FlutterMap(
          mapController: _mapController,
          options: fmap.MapOptions(
            initialCenter: const LatLng(37.5665, 126.9780),
            initialZoom: 15,
          ),
          children: [
            fmap.TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.walking_game',
            ),
            fmap.PolylineLayer(
              polylines: [
                fmap.Polyline(
                  points: _walkingPath,
                  color: Colors.blue,
                  strokeWidth: 4.0,
                ),
              ],
            ),
            fmap.MarkerLayer(
              markers: [
                if (_currentPosition != null)
                  fmap.Marker(
                    point: LatLng(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    ),
                    width: 30,
                    height: 30,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.blue,
                      size: 30,
                    ),
                  ),
              ],
            ),
          ],
        ),
        if (_isTracking)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      '현재 이동 거리: ${(_distanceWalked / 1000).toStringAsFixed(2)}km',
                      style: const TextStyle(fontSize: 18),
                    ),
                    Text(
                      '걸음 수: $_steps',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            onPressed: () {
              if (_currentPosition != null) {
                _mapController?.move(
                  LatLng(
                      _currentPosition!.latitude, _currentPosition!.longitude),
                  15,
                );
              }
            },
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsTab() {
    final nextLevelPoints = _levelThresholds[_level] ?? double.infinity;
    final progress = _points / nextLevelPoints;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'LEVEL $_level',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$_points / $nextLevelPoints',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    progress < 0.3
                        ? Colors.red
                        : progress < 0.7
                            ? Colors.orange
                            : Colors.green,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '다음 레벨까지 ${nextLevelPoints - _points} 포인트',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.5,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: 4,
          itemBuilder: (context, index) {
            final stats = [
              {
                'icon': Icons.directions_walk,
                'title': '총 걸음 수',
                'value': '$_steps'
              },
              {
                'icon': Icons.timeline,
                'title': '총 거리',
                'value': '${(_distanceWalked / 1000).toStringAsFixed(2)}km'
              },
              {'icon': Icons.stars, 'title': '포인트', 'value': '$_points'},
              {
                'icon': Icons.emoji_events,
                'title': '업적',
                'value':
                    '${_unlockedAchievements.length}/${_achievements.length}'
              },
            ];
            final stat = stats[index];
            return Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(stat['icon'] as IconData,
                        size: 30, color: Colors.blue),
                    const SizedBox(height: 8),
                    Text(
                      stat['title'] as String,
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      stat['value'] as String,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAchievementsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '업적',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ..._achievements.map((achievement) {
          final isUnlocked = _unlockedAchievements.contains(achievement);
          return Card(
            elevation: 4,
            margin: const EdgeInsets.only(bottom: 16),
            child: ListTile(
              leading: Icon(
                isUnlocked ? Icons.emoji_events : Icons.lock_outline,
                color: isUnlocked ? Colors.amber : Colors.grey,
                size: 32,
              ),
              title: Text(
                achievement.title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isUnlocked ? Colors.black : Colors.grey,
                ),
              ),
              subtitle: Text(achievement.description),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isUnlocked ? Colors.green : Colors.grey,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '+${achievement.points}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _positionStream?.cancel();
    _simulatorTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }
}

class Achievement {
  final String title;
  final String description;
  final int points;

  Achievement(this.title, this.description, this.points);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Achievement && title == other.title;

  @override
  int get hashCode => title.hashCode;

  @override
  String toString() => '$title|$description|$points';

  factory Achievement.fromString(String str) {
    final parts = str.split('|');
    return Achievement(parts[0], parts[1], int.parse(parts[2]));
  }
}
