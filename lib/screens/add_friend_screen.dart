import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../repositories/friend_repository.dart';

/// Adds a mutual friend by email or user id.
class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key, required this.user, this.repository});

  final User user;
  final FriendRepository? repository;

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  late final FriendRepository _repo = widget.repository ?? FriendRepository();
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() => _error = 'Enter an email or user id.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final friendship = await _repo.addFriend(
        ownerUid: widget.user.uid,
        query: query,
        ownerEmail: widget.user.email,
        ownerDisplayName: widget.user.displayName,
        ownerPhotoURL: widget.user.photoURL,
      );
      final name = friendship.otherProfile(widget.user.uid).label;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _success = '$name is now on your friends list. Sharing starts off.';
        _controller.clear();
      });
    } on FriendLookupException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not add friend: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add friends'),
        backgroundColor: Colors.pink.shade400,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Add someone who already has a LoveHub account, using their email '
              'or user id. You will both be friends, and each of you can choose '
              'what to share.',
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Email or user id',
                hintText: 'friend@example.com',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1),
              label: Text(_busy ? 'Adding…' : 'Add friend'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.pink.shade400,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_success != null) ...[
              const SizedBox(height: 16),
              Text(_success!, style: TextStyle(color: Colors.green.shade800)),
            ],
          ],
        ),
      ),
    );
  }
}
