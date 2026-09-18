import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class InviteScreen extends StatelessWidget {
  final String hubId; // The ID of the circle/hub you are inviting them to

  const InviteScreen({super.key, required this.hubId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invite Partner')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Partner Scan',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Ask your partner to scan this code\nto join your Lovehub.',
            ),
            const SizedBox(height: 40),
            // The QR Code
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: QrImageView(
                data: 'lovehub://join?id=$hubId', // Custom protocol for the app
                version: QrVersions.auto,
                size: 250.0,
                gapless: false,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.pink,
                ),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () {
                // Future: Share link via WhatsApp/SMS
              },
              icon: const Icon(Icons.share),
              label: const Text('Share Invite Link'),
            ),
          ],
        ),
      ),
    );
  }
}
