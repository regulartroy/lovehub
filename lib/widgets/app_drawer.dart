import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/manage_hub_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/invite_screen.dart';
import '../services/member_profile.dart';
import 'member_avatar.dart';

class AppDrawer extends StatelessWidget {
  final User user;
  final Map<String, dynamic> joinedHubs;
  final Map<String, dynamic> pendingHubs;
  final String? activeHubId; // NEW: Knows which hub is active
  final Function(String) onSelectHub; // NEW: Replaced onToggleVisibility
  final VoidCallback onCreateHub;
  final VoidCallback onJoinHub;

  const AppDrawer({
    super.key,
    required this.user,
    required this.joinedHubs,
    required this.pendingHubs,
    required this.activeHubId,
    required this.onSelectHub,
    required this.onCreateHub,
    required this.onJoinHub,
  });

  Future<void> _leaveHub(BuildContext context, String hubId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Leave Hub?"),
        content: const Text(
          "Are you sure you want to leave? You will lose access to all shared data immediately.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Leave", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'joinedHubs.$hubId': FieldValue.delete()},
      );
      await FirebaseFirestore.instance.collection('hubs').doc(hubId).update({
        'members': FieldValue.arrayRemove([user.uid]),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(user.displayName ?? 'Lovehub User'),
            accountEmail: Text(user.email ?? ''),
            currentAccountPicture: MemberAvatar(
              photoURL: user.photoURL,
              name: user.displayName,
              radius: 36,
              backgroundColor: Colors.white,
              foregroundColor: Colors.grey,
              icon: isUsablePhotoUrl(user.photoURL) ? null : Icons.person,
            ),
            decoration: BoxDecoration(color: Colors.pink.shade400),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "My Hubs",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.pink),
                  tooltip: "Create New Hub",
                  onPressed: () {
                    Navigator.pop(context);
                    onCreateHub();
                  },
                ),
              ],
            ),
          ),

          ...(() {
            final sortedHubs = joinedHubs.entries.toList()
              ..sort((a, b) {
                final nameA = (a.value['name'] ?? '').toString().toLowerCase();
                final nameB = (b.value['name'] ?? '').toString().toLowerCase();
                return nameA.compareTo(nameB);
              });

            return sortedHubs.map((entry) {
              final hubId = entry.key;
              final data = entry.value as Map<String, dynamic>;
              final bool isAdmin = data['role'] == 'admin';
              final bool isActive =
                  hubId == activeHubId; // Check if this is the active workspace

              return ListTile(
                selected: isActive,
                selectedTileColor: Colors.pink.shade50,
                onTap: () {
                  onSelectHub(hubId);
                  Navigator.pop(
                    context,
                  ); // Close drawer instantly for snappy feel
                },
                title: Text(
                  data['name'] ?? 'Hub',
                  style: TextStyle(
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    color: isActive ? Colors.pink.shade900 : Colors.black,
                  ),
                ),
                subtitle: Text(
                  isAdmin ? 'Admin' : 'Member',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isActive)
                      const Icon(
                        Icons.check_circle,
                        color: Colors.pink,
                        size: 20,
                      ),
                    if (isAdmin)
                      // --- DIRECT BUTTON FOR ADMINS ---
                      IconButton(
                        icon: const Icon(
                          Icons.settings,
                          size: 20,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          Navigator.pop(context); // Close the drawer
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ManageHubScreen(
                                hubId: hubId,
                                hubName: data['name'],
                                currentUserId: user.uid,
                              ),
                            ),
                          );
                        },
                      )
                    else
                      // --- POPUP FOR REGULAR MEMBERS (Leave Hub) ---
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.settings,
                          size: 20,
                          color: Colors.grey,
                        ),
                        onSelected: (val) {
                          if (val == 'leave') {
                            _leaveHub(context, hubId);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'leave',
                            child: Text(
                              'Leave Hub',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              );
            });
          })(),

          if (pendingHubs.isNotEmpty) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 8),
              child: Text(
                "Pending Approval",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            ...pendingHubs.entries.map(
              (e) => ListTile(
                leading: const Icon(
                  Icons.hourglass_empty,
                  color: Colors.orange,
                  size: 20,
                ),
                title: Text(
                  e.value.toString(),
                  style: const TextStyle(color: Colors.grey),
                ),
                trailing: const Text(
                  "Waiting...",
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
            ),
          ],

          const Divider(),
          if (activeHubId != null) ...[
            ListTile(
              leading: const Icon(Icons.photo_camera_front_outlined, color: Colors.pink),
              title: const Text('Refresh member photos'),
              subtitle: const Text(
                'Copy readable profile photos onto this hub',
                style: TextStyle(fontSize: 11),
              ),
              onTap: () async {
                Navigator.pop(context);
                try {
                  final result = await refreshHubMemberPhotos(
                    hubId: activeHubId!,
                    currentUser: user,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(hubPhotoRefreshMessage(result))),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Could not refresh member photos: $e'),
                      ),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1, color: Colors.pink),
              title: const Text('Invite Partner to Hub'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InviteScreen(hubId: activeHubId!),
                  ),
                );
              },
            ),
          ],
          ListTile(
            leading: const Icon(Icons.pin_rounded, color: Colors.blue),
            title: const Text('Join Hub with Code'),
            onTap: () {
              Navigator.pop(context);
              onJoinHub();
            },
          ),
          ListTile(
            leading: const Icon(Icons.monitor, color: Colors.purple),
            title: const Text('Enter Dashboard Mode'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DashboardScreen(
                    // Dashboard now only opens for the currently active workspace!
                    visibleHubs: joinedHubs.entries
                        .where((e) => e.key == activeHubId)
                        .toList(),
                  ),
                ),
              );
            },
          ),

          const Divider(),

          // --- NEW: LOG OUT BUTTON ---
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            title: const Text(
              'Log Out',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () async {
              Navigator.pop(context); // Close the drawer
              await FirebaseAuth.instance
                  .signOut(); // Instantly triggers AuthGate to show LoginScreen!
            },
          ),

          // --- NEW: VERSION NUMBER ---
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24.0),
            child: Center(
              child: Text(
                'v1.8.2',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24.0),
            child: Center(
              child: Text(
                'Birthdays tweaked on dashboard', // dashboard overhaul
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24.0),
            child: Center(
              child: Text(
                '', // dashboard overhaul
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
