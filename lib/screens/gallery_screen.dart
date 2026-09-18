import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class GalleryScreen extends StatefulWidget {
  final User user;
  final List<MapEntry<String, dynamic>> visibleHubs;

  const GalleryScreen({
    super.key,
    required this.user,
    required this.visibleHubs,
  });

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  bool _isUploading = false;

  Future<void> _uploadPhoto(String hubId) async {
    try {
      // 1. Pick Multiple Images
      final picker = ImagePicker();
      List<XFile> pickedFiles = await picker.pickMultiImage(
        imageQuality: 70, // Squeezes the file size down for fast TV loading!
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (pickedFiles.isEmpty) return;

      // 2. Check the 50-photo limit BEFORE uploading
      final snap = await FirebaseFirestore.instance
          .collection('hubs')
          .doc(hubId)
          .collection('photos')
          .count()
          .get();
      final int currentCount = snap.count ?? 0;

      if (currentCount >= 100) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Photo limit (100) reached! Please delete some first.",
              ),
            ),
          );
        return;
      }

      // If they selected too many, cleanly trim the list down to whatever space is left!
      if (currentCount + pickedFiles.length > 100) {
        final allowed = 100 - currentCount;
        pickedFiles = pickedFiles.take(allowed).toList();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Limit reached! Only uploading $allowed photos."),
            ),
          );
      }

      setState(() => _isUploading = true);

      // 3. Loop through and upload safely (Web & Mobile Compatible!)
      int index = 0;
      for (var pickedFile in pickedFiles) {
        index++;
        final bytes = await pickedFile.readAsBytes();

        // We add the 'index' just in case the loop runs so fast they get the exact same millisecond timestamp!
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${index}_${widget.user.uid}.jpg';
        final storageRef = FirebaseStorage.instance.ref().child(
          'hubs/$hubId/photos/$fileName',
        );

        // Use putData for browser compatibility
        await storageRef.putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        final url = await storageRef.getDownloadURL();

        // 4. Save the URL to Firestore
        await FirebaseFirestore.instance
            .collection('hubs')
            .doc(hubId)
            .collection('photos')
            .add({
              'url': url,
              'storagePath': storageRef.fullPath,
              'uploadedBy': widget.user.uid,
              'createdAt': FieldValue.serverTimestamp(),
            });
      }

      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Upload complete!")));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Upload Error: $e")));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _deletePhoto(
    String hubId,
    String docId,
    String storagePath,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Photo?"),
        content: const Text(
          "This will permanently remove it from the Gallery and the TV Dashboard.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // 1. Delete from Storage
      await FirebaseStorage.instance.ref().child(storagePath).delete();
      // 2. Delete from Firestore
      await FirebaseFirestore.instance
          .collection('hubs')
          .doc(hubId)
          .collection('photos')
          .doc(docId)
          .delete();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Delete Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visibleHubs.isEmpty) {
      return const Scaffold(body: Center(child: Text("Please select a hub")));
    }

    final activeHubId = widget.visibleHubs.first.key;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          "Gallery",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploading ? null : () => _uploadPhoto(activeHubId),
        icon: _isUploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.add_a_photo),
        label: Text(_isUploading ? "Uploading..." : "Add Photo"),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('hubs')
            .doc(activeHubId)
            .collection('photos')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(
              child: CircularProgressIndicator(color: Colors.pink),
            );

          final photos = snapshot.data!.docs;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(
                  "${photos.length} / 100 Photos",
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (photos.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      "No photos yet. Add some to show on the TV!",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3, // 3 photos across
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: photos.length,
                    itemBuilder: (context, index) {
                      final doc = photos[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final String url = data['url'] ?? '';
                      final String storagePath = data['storagePath'] ?? '';

                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          // --- 1. THE HERO IMAGE ---
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                // Fade transition looks much better with Hero animations
                                PageRouteBuilder(
                                  opaque: false,
                                  pageBuilder:
                                      (
                                        context,
                                        animation,
                                        secondaryAnimation,
                                      ) => FullScreenImageViewer(
                                        imageUrl: url,
                                        heroTag: doc
                                            .id, // The unique ID ties the two screens together
                                      ),
                                  transitionsBuilder:
                                      (
                                        context,
                                        animation,
                                        secondaryAnimation,
                                        child,
                                      ) {
                                        return FadeTransition(
                                          opacity: animation,
                                          child: child,
                                        );
                                      },
                                ),
                              );
                            },
                            child: Hero(
                              tag: doc
                                  .id, // The unique ID ties the two screens together
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (ctx, child, progress) {
                                    if (progress == null) return child;
                                    return Container(
                                      color: Colors.grey.shade200,
                                      child: const Center(
                                        child: Icon(
                                          Icons.photo,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),

                          // --- 2. THE DELETE BUTTON (Stays exactly the same) ---
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _deletePhoto(
                                activeHubId,
                                doc.id,
                                storagePath,
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ===========================================================================
// FULL SCREEN PHOTO VIEWER
// ===========================================================================
class FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final String heroTag;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      // Extend body behind app bar so the image is truly full screen
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        // Swipe down to dismiss!
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity! > 200) {
            Navigator.pop(context);
          }
        },
        child: Center(
          // InteractiveViewer gives you pinch-to-zoom for free!
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 4,
            child: Hero(
              tag: heroTag, // This MUST match the tag in the grid!
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
