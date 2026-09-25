import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'screens/gallery_screen.dart';
// SCREEN IMPORTS
import 'screens/feed_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/finance_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/cleaning_screen.dart';
import 'screens/food_screen.dart'; // Ensure this file exists
import 'firebase_options.dart';
import 'screens/invite_screen.dart'; // Make sure the path matches your structure
import 'widgets/app_drawer.dart';
import 'screens/cycle_screen.dart'; // <-- Add this!
import 'services/member_profile.dart';
import 'services/web_update_firestore.dart';
import 'widgets/web_update_host.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const LovehubApp());
}

class LovehubApp extends StatefulWidget {
  const LovehubApp({super.key});

  @override
  State<LovehubApp> createState() => _LovehubAppState();
}

class _LovehubAppState extends State<LovehubApp> {
  final _sheetTracker = WebUpdateSheetTracker();
  late final Stream<String?>? _webBuildUpdates = kIsWeb
      ? watchWebBuildStamp()
      : null;

  @override
  void dispose() {
    _sheetTracker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lovehub',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [_sheetTracker],
      builder: (context, child) {
        return WebUpdateHost(
          enabled: kIsWeb,
          sheetOpen: _sheetTracker,
          remoteUpdates: _webBuildUpdates,
          fetchRemote: kIsWeb ? fetchWebBuildStamp : null,
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.pink,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) return const MainScreen();
        return const LoginScreen();
      },
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  Future<void> _handleLogin() async {
    try {
      GoogleAuthProvider authProvider = GoogleAuthProvider();
      authProvider.setCustomParameters({'prompt': 'select_account'});
      await FirebaseAuth.instance.signInWithPopup(authProvider);
    } catch (e) {
      print("Login Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logo.png',
              height: 120,
              width: 120,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 20),
            const Text(
              "Lovehub",
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            FilledButton.icon(
              onPressed: _handleLogin,
              icon: const Icon(Icons.login),
              label: const Text("Sign in with Google"),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  User? _user;
  late TabController _tabController;
  bool _isLoadingUser = true; // <-- NEW: Stop the flash!

  // Clean Data Pipeline from the User Document
  Map<String, dynamic> _joinedHubs = {};
  Map<String, dynamic> _pendingHubs = {};
  List<MapEntry<String, dynamic>> _visibleHubs = [];
  bool _didSyncHubPhotos = false;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    _tabController = TabController(length: 8, vsync: this);
    _initUserPipeline();
  }

  // Listens to the USER document, not the hubs directly. This makes toggles work!
  // --- REPLACE _initUserPipeline WITH THIS ---
  void _initUserPipeline() {
    if (_user == null) return;

    FirebaseFirestore.instance.collection('users').doc(_user!.uid).snapshots().listen((
      doc,
    ) async {
      if (!mounted) return;

      if (!doc.exists) {
        // First time user! Create profile and personal hub.
        // First time user! Create profile and personal hub.
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_user!.uid)
            .set({
              'email': _user!.email,
              'displayName': _user!.displayName,
              'photoURL': _user!.photoURL,
              'createdAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true)); // <--- ADD THIS MERGE OPTION!

        _createPersonalHub();
      } else {
        final data = doc.data()!;
        final profileUpdates = currentUserProfileUpdates(
          authPhotoURL: _user!.photoURL,
          authDisplayName: _user!.displayName,
          existing: data,
        );
        if (profileUpdates != null) {
          FirebaseFirestore.instance
              .collection('users')
              .doc(_user!.uid)
              .set(profileUpdates, SetOptions(merge: true));
        }

        setState(() {
          _joinedHubs = data['joinedHubs'] ?? {};
          _pendingHubs = data['pendingHubs'] ?? {};

          // SMART WORKSPACE ROUTING
          String? activeId = data['activeHubId'];

          // If no active hub is set, or the active hub was deleted/left, pick the first available one
          if (activeId == null || !_joinedHubs.containsKey(activeId)) {
            if (_joinedHubs.isNotEmpty) {
              // Get the first alphabetically sorted hub
              final sortedKeys = _joinedHubs.keys.toList()
                ..sort(
                  (a, b) => (_joinedHubs[a]['name'] ?? '')
                      .toString()
                      .toLowerCase()
                      .compareTo(
                        (_joinedHubs[b]['name'] ?? '').toString().toLowerCase(),
                      ),
                );
              activeId = sortedKeys.first;

              // Save this back to Firestore silently
              FirebaseFirestore.instance
                  .collection('users')
                  .doc(_user!.uid)
                  .update({'activeHubId': activeId});
            }
          }

          // Force _visibleHubs to ONLY contain the active workspace.
          // This magically fixes Feed, Tasks, Calendar, etc., without rewriting them!
          if (activeId != null && _joinedHubs.containsKey(activeId)) {
            _visibleHubs = [MapEntry(activeId, _joinedHubs[activeId])];
          } else {
            _visibleHubs = [];
          }

          _isLoadingUser =
              false; // <-- NEW: Data has arrived, turn off the loader!
        });

        if (!_didSyncHubPhotos) {
          final hubIds = Map<String, dynamic>.from(
            data['joinedHubs'] ?? {},
          ).keys;
          if (hubIds.isNotEmpty) {
            _didSyncHubPhotos = true;
            syncCurrentUserPhotoToHubs(hubIds: hubIds, user: _user);
          }
        }
      }
    });
  }

  // --- REPLACE _toggleHubVisibility WITH THIS ---
  void _selectHub(String hubId) {
    // Instantly switch the active workspace in the database
    FirebaseFirestore.instance.collection('users').doc(_user!.uid).update({
      'activeHubId': hubId,
    });
  }

  Future<void> _createPersonalHub() async {
    // 1. Create the hub
    final docRef = await FirebaseFirestore.instance
        .collection('hubs')
        .add(
          newHubDocument(
            name: 'My Lovehub',
            creatorUid: _user!.uid,
            photoURL: _user!.photoURL,
            displayName: _user!.displayName,
          ),
        );
    // 2. Add it to the user's joinedHubs so it shows up
    await FirebaseFirestore.instance.collection('users').doc(_user!.uid).set({
      'joinedHubs': {
        docRef.id: {'name': 'My Lovehub', 'isVisible': true, 'role': 'admin'},
      },
    }, SetOptions(merge: true));
  }

  // Secure Join Flow - Creates a request!
  void _showJoinHubDialog() {
    final TextEditingController codeCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Join a Hub"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Paste the Hub ID or invite link:",
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(
                hintText: "e.g. abc123xyz...",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () async {
              String hubId = codeCtrl.text.trim();
              if (hubId.isEmpty) return;
              if (hubId.startsWith("lovehub://join?id="))
                hubId = hubId.replaceAll("lovehub://join?id=", "");

              try {
                // Check if hub exists
                final hubDoc = await FirebaseFirestore.instance
                    .collection('hubs')
                    .doc(hubId)
                    .get();
                if (!hubDoc.exists) throw Exception("Hub not found");

                // 1. Write to Hub Requests collection
                await FirebaseFirestore.instance
                    .collection('hubs')
                    .doc(hubId)
                    .collection('requests')
                    .doc(_user!.uid)
                    .set({
                      'uid': _user!.uid,
                      'displayName': _user!.displayName ?? 'Unknown',
                      'photoURL': _user!.photoURL,
                      'requestedAt': FieldValue.serverTimestamp(),
                    });

                // 2. Add to User's Pending Hubs list
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(_user!.uid)
                    .set({
                      'pendingHubs': {
                        hubId: hubDoc.data()?['name'] ?? 'Unknown Hub',
                      },
                    }, SetOptions(merge: true));

                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Request sent to Hub Admin!")),
                  );
                }
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Error: Could not find that Hub."),
                    ),
                  );
              }
            },
            child: const Text("Send Request"),
          ),
        ],
      ),
    );
  }

  void _createHubDialog() {
    final TextEditingController nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Create New Hub"),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            hintText: "Hub Name (e.g. The Smiths)",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty) {
                final docRef = await FirebaseFirestore.instance
                    .collection('hubs')
                    .add(
                      newHubDocument(
                        name: nameCtrl.text,
                        creatorUid: _user!.uid,
                        photoURL: _user!.photoURL,
                        displayName: _user!.displayName,
                      ),
                    );
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(_user!.uid)
                    .set({
                      'joinedHubs': {
                        docRef.id: {
                          'name': nameCtrl.text,
                          'isVisible': true,
                          'role': 'admin',
                        },
                      },
                    }, SetOptions(merge: true));
                if (mounted) Navigator.pop(ctx);
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  void _toggleHubVisibility(String hubId, bool isVisible) {
    FirebaseFirestore.instance.collection('users').doc(_user!.uid).update({
      'joinedHubs.$hubId.isVisible': isVisible,
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) return const LoginScreen();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Lovehub",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.pink),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.settings), // Changed to a cog!
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      // We finally use your custom AppDrawer!
      // We finally use your custom AppDrawer!
      endDrawer: AppDrawer(
        user: _user!,
        joinedHubs: _joinedHubs,
        pendingHubs: _pendingHubs,
        activeHubId: _visibleHubs.isNotEmpty
            ? _visibleHubs.first.key
            : null, // NEW
        onSelectHub: _selectHub, // NEW
        onCreateHub: _createHubDialog,
        onJoinHub: _showJoinHubDialog,
      ),
      body: _isLoadingUser
          ? const Center(
              child: CircularProgressIndicator(color: Colors.pink),
            ) // Show spinner while loading
          : _visibleHubs.isEmpty
          ? Center(
              child: _pendingHubs.isNotEmpty
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.hourglass_empty,
                          size: 60,
                          color: Colors.orange.shade400,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          "Request Sent!",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Waiting for approval to join:\n${_pendingHubs.values.first}",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/logo.png',
                          height: 80,
                          width: 80,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          "Welcome to Lovehub!",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "Join your partner or create a new space.",
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 30),
                        FilledButton.icon(
                          onPressed: _createHubDialog,
                          icon: const Icon(Icons.add),
                          label: const Text("Create a New Hub"),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _showJoinHubDialog,
                          icon: const Icon(Icons.pin_rounded),
                          label: const Text("Join with a Code"),
                        ),
                      ],
                    ),
            )
          : TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // We pass _joinedHubs and _pendingHubs into FeedScreen now!
                FeedScreen(
                  user: _user!,
                  visibleHubs: _visibleHubs,
                  joinedHubs: _joinedHubs,
                  pendingHubs: _pendingHubs,
                ),
                CalendarScreen(user: _user!, onSyncRequest: (i) async {}),
                TasksScreen(user: _user!, visibleHubs: _visibleHubs),
                FoodScreen(user: _user!, visibleHubs: _visibleHubs),
                CleaningScreen(user: _user!, visibleHubs: _visibleHubs),
                FinanceScreen(user: _user!, visibleHubs: _visibleHubs),
                GalleryScreen(
                  user: _user!,
                  visibleHubs: _visibleHubs,
                ), // <-- NEW!
                CycleScreen(user: _user!, visibleHubs: _visibleHubs),
              ],
            ),
      bottomNavigationBar: Container(
        color: Colors.white,
        child: SafeArea(
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.pink,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.pink,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(icon: Icon(Icons.dashboard), text: "Home"),
              Tab(icon: Icon(Icons.calendar_month), text: "Calendar"),
              Tab(icon: Icon(Icons.check_circle_outline), text: "Tasks"),
              Tab(icon: Icon(Icons.restaurant), text: "Food"),
              Tab(icon: Icon(Icons.cleaning_services), text: "Rota"),
              Tab(icon: Icon(Icons.attach_money), text: "Finance"),
              Tab(icon: Icon(Icons.photo_library), text: "Gallery"), // <-- NEW!
              Tab(icon: Icon(Icons.water_drop), text: "Cycle"),
            ],
          ),
        ),
      ),
    );
  }
}
