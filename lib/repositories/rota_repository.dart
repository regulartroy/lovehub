import 'package:cloud_firestore/cloud_firestore.dart';

class RotaRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ===========================================================================
  // THE 8-WEEK "WEEKLY POOL" GENERATOR (Strict Alternation Edition!)
  // ===========================================================================
  // ===========================================================================
  // THE 8-WEEK "WEEKLY POOL" GENERATOR (Smart Escape Hatch Edition!)
  // ===========================================================================
  Future<void> generateWeeklyBlueprint({
    required String hubId,
    required List<Map<String, dynamic>> chores,
    required DateTime startDate,
  }) async {
    Map<String, List<Map<String, dynamic>>> finalBlueprint = {
      for (int i = 1; i <= 8; i++) "$i": [],
    };

    Map<int, int> weekLoads = {for (int i = 1; i <= 8; i++) i: 0};
    Map<String, int> totalUserLoads = {};
    Map<int, Map<String, int>> userLoadsPerWeek = {
      for (int i = 1; i <= 8; i++) i: {},
    };

    List<Map<String, dynamic>> sortedChores = List.from(chores);
    // Sort heaviest tasks first so they get distributed optimally!
    sortedChores.sort(
      (a, b) =>
          (b['effortMinutes'] as int).compareTo(a['effortMinutes'] as int),
    );

    for (var chore in sortedChores) {
      int freq = (chore['frequencyDays'] ?? 7) as int;
      int effort = (chore['effortMinutes'] ?? 15) as int;
      List<dynamic> eligible = chore['eligibleUsers'] ?? [];

      String lastAssignedUser = "";

      void assignToWeek(int weekNum, {String instanceSuffix = ""}) {
        String bestUser = 'unassigned';

        if (freq >= 28) {
          bestUser = 'shared';
        } else if (eligible.isNotEmpty) {
          List<String> validUsers = List.from(eligible);

          // --- THE SMART ESCAPE HATCH ---
          if (validUsers.length > 1 &&
              lastAssignedUser.isNotEmpty &&
              validUsers.contains(lastAssignedUser)) {
            int minOtherLoad = 999999;
            for (String u in validUsers) {
              if (u != lastAssignedUser) {
                int wl = userLoadsPerWeek[weekNum]![u] ?? 0;
                if (wl < minOtherLoad) minOtherLoad = wl;
              }
            }
            int lastUserLoad =
                userLoadsPerWeek[weekNum]![lastAssignedUser] ?? 0;

            // If alternating means the OTHER person will be significantly busier this week (> 10 mins),
            // we BREAK the rule and leave both users valid so the load balancer can fix the week!
            if ((minOtherLoad - lastUserLoad) <= 10) {
              validUsers.remove(lastAssignedUser);
            }
          }

          bestUser = validUsers.first;
          int minWeeklyLoad = 999999;
          int minTotalLoad = 999999;

          for (String uid in validUsers) {
            int weeklyLoad = userLoadsPerWeek[weekNum]![uid] ?? 0;
            int totalLoad = totalUserLoads[uid] ?? 0;

            if (weeklyLoad < minWeeklyLoad) {
              minWeeklyLoad = weeklyLoad;
              minTotalLoad = totalLoad;
              bestUser = uid;
            } else if (weeklyLoad == minWeeklyLoad &&
                totalLoad < minTotalLoad) {
              minTotalLoad = totalLoad;
              bestUser = uid;
            }
          }
        }

        String baseId =
            chore['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();

        finalBlueprint[weekNum.toString()]!.add({
          'id': '$baseId$instanceSuffix',
          'title': chore['title'],
          'effortMinutes': effort,
          'assignedTo': bestUser,
        });

        if (bestUser != 'shared' && bestUser != 'unassigned') {
          totalUserLoads[bestUser] = (totalUserLoads[bestUser] ?? 0) + effort;
          userLoadsPerWeek[weekNum]![bestUser] =
              (userLoadsPerWeek[weekNum]![bestUser] ?? 0) + effort;
          lastAssignedUser = bestUser;
        }
        weekLoads[weekNum] = weekLoads[weekNum]! + effort;
      }

      if (freq <= 3) {
        // TWICE WEEKLY
        for (int w = 1; w <= 8; w++) {
          assignToWeek(w, instanceSuffix: "_1");
          assignToWeek(w, instanceSuffix: "_2");
        }
      } else if (freq <= 7) {
        // WEEKLY
        for (int w = 1; w <= 8; w++) assignToWeek(w);
      } else if (freq <= 14) {
        // FORTNIGHTLY
        int oddLoad =
            weekLoads[1]! + weekLoads[3]! + weekLoads[5]! + weekLoads[7]!;
        int evenLoad =
            weekLoads[2]! + weekLoads[4]! + weekLoads[6]! + weekLoads[8]!;
        if (oddLoad <= evenLoad) {
          for (int w in [1, 3, 5, 7]) assignToWeek(w);
        } else {
          for (int w in [2, 4, 6, 8]) assignToWeek(w);
        }
      } else {
        // MONTHLY (Shared)
        int bestW1 = 1;
        for (int w = 2; w <= 4; w++) {
          if (weekLoads[w]! < weekLoads[bestW1]!) bestW1 = w;
        }
        assignToWeek(bestW1, instanceSuffix: "_m1");

        int bestW2 = 5;
        for (int w = 6; w <= 8; w++) {
          if (weekLoads[w]! < weekLoads[bestW2]!) bestW2 = w;
        }
        assignToWeek(bestW2, instanceSuffix: "_m2");
      }
    }

    await _db
        .collection('hubs')
        .doc(hubId)
        .collection('rota_settings')
        .doc('config')
        .set({
          'blueprint': finalBlueprint,
          'rawChores': chores,
          'anchorDate': Timestamp.fromDate(startDate),
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Stream<Map<String, dynamic>?> streamRotaConfig(String hubId) {
    return _db
        .collection('hubs')
        .doc(hubId)
        .collection('rota_settings')
        .doc('config')
        .snapshots()
        .map((doc) => doc.data());
  }
}
