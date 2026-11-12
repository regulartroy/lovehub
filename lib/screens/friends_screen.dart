import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/friend_model.dart';
import '../repositories/friend_repository.dart';
import '../services/member_profile.dart';
import '../widgets/member_avatar.dart';

/// Alternative sharing: a friends list with per-friend work / personal /
/// birthday toggles. This sits alongside hubs; it does not replace them.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, required this.user, this.repository});

  final User user;
  final FriendRepository? repository;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late final FriendRepository _repo = widget.repository ?? FriendRepository();

  Future<void> _addFriend() async {
    final controller = TextEditingController();
    final query = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a friend'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email or user id',
            hintText: 'friend@example.com',
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (query == null || query.trim().isEmpty) return;

    try {
      await _repo.addFriend(
        ownerUid: widget.user.uid,
        query: query,
        ownerEmail: widget.user.email,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Friend added. Sharing starts off.')),
      );
    } on FriendLookupException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add friend: $e')));
    }
  }

  Future<void> _removeFriend(FriendModel friend) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove friend?'),
        content: Text(
          'Remove ${friend.label} from your friends list? '
          'This does not change any hubs.',
        ),
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
    await _repo.removeFriend(ownerUid: widget.user.uid, friendUid: friend.id);
  }

  Future<void> _setShare(
    FriendModel friend,
    FriendShareKind kind,
    bool value,
  ) async {
    await _repo.setShare(
      ownerUid: widget.user.uid,
      friendUid: friend.id,
      kind: kind,
      value: value,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        backgroundColor: Colors.pink.shade400,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addFriend,
        backgroundColor: Colors.pink.shade400,
        tooltip: 'Add a friend',
        child: const Icon(Icons.person_add_alt_1),
      ),
      body: StreamBuilder<List<FriendModel>>(
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
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Add a friend by email, then choose what you share '
                  'with them: work, personal, or birthdays. '
                  'This sits alongside your hubs and does not replace them.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: friends.length,
            itemBuilder: (context, index) => _FriendCard(
              friend: friends[index],
              onShareChanged: _setShare,
              onRemove: _removeFriend,
            ),
          );
        },
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  const _FriendCard({
    required this.friend,
    required this.onShareChanged,
    required this.onRemove,
  });

  final FriendModel friend;
  final Future<void> Function(FriendModel, FriendShareKind, bool)
  onShareChanged;
  final Future<void> Function(FriendModel) onRemove;

  @override
  Widget build(BuildContext context) {
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
                photoURL: friend.photoURL,
                name: friend.label,
                radius: 22,
                backgroundColor: Colors.pink.shade100,
                foregroundColor: Colors.pink.shade800,
                icon: isUsablePhotoUrl(friend.photoURL) ? null : Icons.person,
              ),
              title: Text(
                friend.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: friend.email != null && friend.email!.isNotEmpty
                  ? Text(friend.email!)
                  : null,
              trailing: IconButton(
                tooltip: 'Remove friend',
                icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                onPressed: () => onRemove(friend),
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
              value: friend.shareWork,
              activeThumbColor: Colors.pink.shade400,
              onChanged: (v) => onShareChanged(friend, FriendShareKind.work, v),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Personal'),
              value: friend.sharePersonal,
              activeThumbColor: Colors.pink.shade400,
              onChanged: (v) =>
                  onShareChanged(friend, FriendShareKind.personal, v),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Birthdays'),
              value: friend.shareBirthdays,
              activeThumbColor: Colors.pink.shade400,
              onChanged: (v) =>
                  onShareChanged(friend, FriendShareKind.birthdays, v),
            ),
          ],
        ),
      ),
    );
  }
}
