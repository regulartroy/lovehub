import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/friend_model.dart';
import '../repositories/friend_repository.dart';
import '../services/member_profile.dart';
import '../widgets/member_avatar.dart';
import 'add_friend_screen.dart';

/// Per-friend sharing toggles for the friends-based model.
class SharingScreen extends StatefulWidget {
  const SharingScreen({super.key, required this.user, this.repository});

  final User user;
  final FriendRepository? repository;

  @override
  State<SharingScreen> createState() => _SharingScreenState();
}

class _SharingScreenState extends State<SharingScreen> {
  late final FriendRepository _repo = widget.repository ?? FriendRepository();

  void _openAddFriend() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddFriendScreen(user: widget.user, repository: _repo),
      ),
    );
  }

  Future<void> _removeFriend(Friendship friendship) async {
    final other = friendship.otherProfile(widget.user.uid);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove friend?'),
        content: Text('Remove ${other.label} from your friends list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _repo.removeFriend(friendship.id);
  }

  Future<void> _setShare(
    Friendship friendship,
    FriendShareKind kind,
    bool value,
  ) async {
    await _repo.setShare(
      friendshipId: friendship.id,
      ownerUid: widget.user.uid,
      kind: kind,
      value: value,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sharing'),
        backgroundColor: Colors.pink.shade400,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Add a friend',
            onPressed: _openAddFriend,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddFriend,
        backgroundColor: Colors.pink.shade400,
        tooltip: 'Add a friend',
        child: const Icon(Icons.person_add_alt_1),
      ),
      body: StreamBuilder<List<Friendship>>(
        stream: _repo.watch(widget.user.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load friends: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final friends = snapshot.data!;
          if (friends.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Add a friend, then choose what you share with them: '
                      'work, personal, or birthdays.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _openAddFriend,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Add a friend'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.pink.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: friends.length,
            itemBuilder: (context, index) {
              final friendship = friends[index];
              return _FriendShareCard(
                friendship: friendship,
                myUid: widget.user.uid,
                onShareChanged: _setShare,
                onRemove: _removeFriend,
              );
            },
          );
        },
      ),
    );
  }
}

class _FriendShareCard extends StatelessWidget {
  const _FriendShareCard({
    required this.friendship,
    required this.myUid,
    required this.onShareChanged,
    required this.onRemove,
  });

  final Friendship friendship;
  final String myUid;
  final Future<void> Function(Friendship, FriendShareKind, bool) onShareChanged;
  final Future<void> Function(Friendship) onRemove;

  @override
  Widget build(BuildContext context) {
    final other = friendship.otherProfile(myUid);
    final mine = friendship.mySharing(myUid);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: MemberAvatar(
                photoURL: other.photoURL,
                name: other.label,
                radius: 22,
                backgroundColor: Colors.pink.shade100,
                foregroundColor: Colors.pink.shade800,
                icon: isUsablePhotoUrl(other.photoURL) ? null : Icons.person,
              ),
              title: Text(
                other.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: other.email != null && other.email!.isNotEmpty
                  ? Text(other.email!)
                  : null,
              trailing: IconButton(
                tooltip: 'Remove friend',
                icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                onPressed: () => onRemove(friendship),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 16, bottom: 4),
              child: Text(
                'Share with them',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Work'),
              value: mine.shareWork,
              activeThumbColor: Colors.pink.shade400,
              onChanged: (v) =>
                  onShareChanged(friendship, FriendShareKind.work, v),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Personal'),
              value: mine.sharePersonal,
              activeThumbColor: Colors.pink.shade400,
              onChanged: (v) =>
                  onShareChanged(friendship, FriendShareKind.personal, v),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Birthdays'),
              value: mine.shareBirthdays,
              activeThumbColor: Colors.pink.shade400,
              onChanged: (v) =>
                  onShareChanged(friendship, FriendShareKind.birthdays, v),
            ),
          ],
        ),
      ),
    );
  }
}
