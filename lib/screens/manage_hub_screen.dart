// File: lib/screens/manage_hub_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/member_profile.dart';
import '../widgets/member_avatar.dart';

class ManageHubScreen extends StatelessWidget {
  final String hubId;
  final String hubName;
  final String currentUserId;

  const ManageHubScreen({
    super.key,
    required this.hubId,
    required this.hubName,
    required this.currentUserId,
  });

  // --- ACTIONS ---

  Future<void> _approveUser(
    BuildContext context,
    Map<String, dynamic> requestData,
  ) async {
    final newMemberId = requestData['uid'].toString();
    final best = await resolveJoinMemberProfile(
      uid: newMemberId,
      requestPhotoURL: requestData['photoURL']?.toString(),
      requestDisplayName: requestData['displayName']?.toString(),
    );
    final requestPhoto = best.photoURL;
    final requestName = best.displayName;

    final hubUpdates = <String, dynamic>{
      'members': FieldValue.arrayUnion([newMemberId]),
      ...hubMemberProfilePayload(
        uid: newMemberId,
        photoURL: requestPhoto,
        displayName: requestName,
      ),
    };

    await FirebaseFirestore.instance.collection('hubs').doc(hubId).set(
      hubUpdates,
      SetOptions(merge: true),
    );

    final userUpdates = <String, dynamic>{
      'joinedHubs': {
        hubId: {'name': hubName, 'isVisible': true, 'role': 'member'},
      },
      'pendingHubs': {hubId: FieldValue.delete()},
    };
    if (isUsablePhotoUrl(requestPhoto)) {
      userUpdates['photoURL'] = requestPhoto;
    }
    if (requestName != null && requestName.trim().isNotEmpty) {
      userUpdates['displayName'] = requestName;
    }

    await FirebaseFirestore.instance.collection('users').doc(newMemberId).set(
      userUpdates,
      SetOptions(merge: true),
    );

    await FirebaseFirestore.instance
        .collection('hubs')
        .doc(hubId)
        .collection('requests')
        .doc(newMemberId)
        .delete();

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Member Approved!")));
    }
  }

  Future<void> _refreshMemberPhotos(BuildContext context) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final result = await refreshHubMemberPhotos(
        hubId: hubId,
        currentUser: FirebaseAuth.instance.currentUser,
      );
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hubPhotoRefreshMessage(result))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not refresh member photos: $e')),
        );
      }
    }
  }

  Future<void> _rejectUser(String userId) async {
    await FirebaseFirestore.instance
        .collection('hubs')
        .doc(hubId)
        .collection('requests')
        .doc(userId)
        .delete();
  }

  // --- NEW: RENAME HUB FUNCTION ---
  Future<void> _renameHub(BuildContext context) async {
    final TextEditingController nameCtrl = TextEditingController(text: hubName);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rename Hub"),
        content: TextField(
          controller: nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: "New Hub Name (e.g. The Smiths)",
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != hubName) {
      try {
        final hubDoc = await FirebaseFirestore.instance
            .collection('hubs')
            .doc(hubId)
            .get();
        final List members = hubDoc.data()?['members'] ?? [];

        final batch = FirebaseFirestore.instance.batch();

        // 1. Rename the main hub
        batch.update(FirebaseFirestore.instance.collection('hubs').doc(hubId), {
          'name': newName,
        });

        // 2. Rename it in EVERY member's profile
        for (String uid in members) {
          batch.update(
            FirebaseFirestore.instance.collection('users').doc(uid),
            {'joinedHubs.$hubId.name': newName},
          );
        }

        await batch.commit();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Hub renamed successfully!")),
          );
          Navigator.pop(
            context,
          ); // Pop back to feed to see the new name instantly
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Error renaming hub: $e")));
        }
      }
    }
  }

  Future<void> _deleteHub(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Hub?", style: TextStyle(color: Colors.red)),
        content: Text(
          "Are you sure you want to permanently delete '$hubName'?\n\n"
          "This action cannot be undone. All lists, events, and members will lose access immediately.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete Permanently"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final hubDoc = await FirebaseFirestore.instance
          .collection('hubs')
          .doc(hubId)
          .get();
      final List members = hubDoc.data()?['members'] ?? [];
      final batch = FirebaseFirestore.instance.batch();

      for (String uid in members) {
        final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
        batch.update(userRef, {'joinedHubs.$hubId': FieldValue.delete()});
      }

      final hubRef = FirebaseFirestore.instance.collection('hubs').doc(hubId);
      batch.delete(hubRef);

      await batch.commit();

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Hub deleted successfully.")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error deleting hub: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Manage $hubName")),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- SECTION 1: PENDING REQUESTS ---
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('hubs')
                  .doc(hubId)
                  .collection('requests')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                  return const SizedBox();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: Colors.orange.shade100,
                      child: const Text(
                        "⚠️ Pending Requests",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      ),
                    ),
                    ...snapshot.data!.docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return ListTile(
                        title: Text(data['displayName']),
                        subtitle: const Text("Wants to join"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _rejectUser(data['uid']),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.check,
                                color: Colors.green,
                              ),
                              onPressed: () => _approveUser(context, data),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                );
              },
            ),

            // --- SECTION 2: CURRENT MEMBERS ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "Current Members",
                style: TextStyle(
                  color: Colors.pink.shade900,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),

            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('hubs')
                  .doc(hubId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || !snapshot.data!.exists)
                  return const Center(child: Text("Hub not found"));
                final hubData = snapshot.data!.data() as Map<String, dynamic>;
                final List members = hubData['members'] ?? [];

                final profiles = Map<String, dynamic>.from(
                  hubData['memberProfiles'] ?? const {},
                );
                return Column(
                  children: members.map((uid) {
                    return MemberTile(
                      userId: uid,
                      hubId: hubId,
                      isMe: uid == currentUserId,
                      hubProfile: hubProfileMap(profiles[uid]),
                    );
                  }).toList(),
                );
              },
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _refreshMemberPhotos(context),
                  icon: const Icon(Icons.photo_camera_front_outlined),
                  label: const Text("Refresh member photos"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                "Re-pulls Google photos from each member's profile when LoveHub can read them, and writes them onto this hub so partners keep seeing them.",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),

            const Divider(height: 40),

            // --- SECTION 3: ACTIONS ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "Hub Actions",
                style: TextStyle(
                  color: Colors.pink.shade900,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _renameHub(context),
                  icon: const Icon(Icons.edit),
                  label: const Text("Rename Hub"),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _deleteHub(context),
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  label: const Text(
                    "Delete Hub",
                    style: TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class MemberTile extends StatelessWidget {
  final String userId;
  final String hubId;
  final bool isMe;
  final Map<String, dynamic> hubProfile;

  const MemberTile({
    super.key,
    required this.userId,
    required this.hubId,
    required this.isMe,
    this.hubProfile = const {},
  });

  Future<void> _updateRole(String newRole) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'joinedHubs.$hubId.role': newRole,
    });
  }

  Future<void> _removeUser() async {
    await FirebaseFirestore.instance.collection('hubs').doc(hubId).update({
      'members': FieldValue.arrayRemove([userId]),
    });
    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'joinedHubs.$hubId': FieldValue.delete(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return const ListTile(leading: CircularProgressIndicator());
        }

        final userData = snapshot.data?.data() as Map<String, dynamic>?;
        final photoURL = resolveMemberPhotoUrl(
          uid: userId,
          firestorePhotoURL: userData?['photoURL']?.toString(),
          hubPhotoURL: hubProfile['photoURL']?.toString(),
          currentUid: isMe ? userId : null,
          currentAuthPhotoURL: isMe
              ? FirebaseAuth.instance.currentUser?.photoURL
              : null,
        );
        final displayName =
            (userData?['displayName'] ?? hubProfile['displayName'] ?? 'Unknown')
                .toString();

        final hubData = userData?['joinedHubs']?[hubId] as Map<String, dynamic>?;
        final role = hubData?['role'] ?? 'member';
        final isAdmin = role == 'admin';

        return ListTile(
          leading: MemberAvatar(
            photoURL: photoURL,
            name: displayName,
            radius: 20,
            backgroundColor: Colors.pink.shade200,
          ),
          title: Text(displayName),
          subtitle: Text(isAdmin ? "Admin" : "Member"),
          trailing: isMe
              ? const Chip(label: Text("You"))
              : PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'promote') _updateRole('admin');
                    if (value == 'demote') _updateRole('member');
                    if (value == 'remove') _removeUser();
                  },
                  itemBuilder: (context) => [
                    if (!isAdmin)
                      const PopupMenuItem(
                        value: 'promote',
                        child: Text("Promote to Admin"),
                      ),
                    if (isAdmin)
                      const PopupMenuItem(
                        value: 'demote',
                        child: Text("Demote to Member"),
                      ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Text(
                        "Remove from Hub",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
