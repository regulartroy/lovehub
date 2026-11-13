import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/friend_model.dart';
import '../repositories/friend_repository.dart';
import '../services/member_profile.dart';
import '../widgets/member_avatar.dart';

/// Adds a mutual friend by email, user id, or from people you already share a hub with.
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
  String? _addingUid;
  String? _error;
  String? _success;
  List<HubFriendSuggestion> _suggestions = [];
  bool _suggestionsLoading = true;
  StreamSubscription<List<Friendship>>? _friendsSub;

  @override
  void initState() {
    super.initState();
    _friendsSub = _repo.watch(widget.user.uid).listen((friends) {
      if (!mounted) return;
      final already = friends
          .map((f) => f.otherUid(widget.user.uid))
          .whereType<String>()
          .toSet();
      _loadSuggestions(already);
    });
  }

  Future<void> _loadSuggestions(Set<String> alreadyFriendUids) async {
    try {
      final list = await _repo.suggestionsFromExistingHubs(
        ownerUid: widget.user.uid,
        alreadyFriendUids: alreadyFriendUids,
      );
      if (!mounted) return;
      setState(() {
        _suggestions = list;
        _suggestionsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _suggestionsLoading = false);
    }
  }

  @override
  void dispose() {
    _friendsSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add({String? query, HubFriendSuggestion? suggestion}) async {
    final value = query?.trim().isNotEmpty == true
        ? query!.trim()
        : suggestion?.uid;
    if (value == null || value.isEmpty) {
      setState(() => _error = 'Enter an email or user id.');
      return;
    }
    setState(() {
      _busy = true;
      _addingUid = suggestion?.uid;
      _error = null;
      _success = null;
    });
    try {
      final friendship = await _repo.addFriend(
        ownerUid: widget.user.uid,
        query: value,
        ownerEmail: widget.user.email,
        ownerDisplayName: widget.user.displayName,
        ownerPhotoURL: widget.user.photoURL,
      );
      final name =
          suggestion?.label ?? friendship.otherProfile(widget.user.uid).label;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _addingUid = null;
        _success = '$name is now on your friends list. Sharing starts off.';
        _controller.clear();
      });
    } on FriendLookupException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _addingUid = null;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _addingUid = null;
        _error = 'Could not add friend: $e';
      });
    }
  }

  Future<void> _submit() => _add(query: _controller.text);

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
            if (_suggestionsLoading)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: LinearProgressIndicator(),
              )
            else if (_suggestions.isNotEmpty) ...[
              const Text(
                'People you already share a hub with',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (final suggestion in _suggestions)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: MemberAvatar(
                      photoURL: suggestion.photoURL,
                      name: suggestion.label,
                      radius: 20,
                      backgroundColor: Colors.pink.shade100,
                      foregroundColor: Colors.pink.shade800,
                      icon: isUsablePhotoUrl(suggestion.photoURL)
                          ? null
                          : Icons.person,
                    ),
                    title: Text(suggestion.label),
                    subtitle: Text(suggestion.hubSummary),
                    trailing: FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _add(suggestion: suggestion),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.pink.shade400,
                      ),
                      child: _addingUid == suggestion.uid
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Add'),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
            ],
            const Text(
              'Or add someone by email or user id. You will both be friends, '
              'and each of you can choose what to share.',
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
              icon: _busy && _addingUid == null
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1),
              label: Text(
                _busy && _addingUid == null ? 'Adding…' : 'Add friend',
              ),
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
