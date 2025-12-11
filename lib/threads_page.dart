// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
// import 'package:socket_io_client/socket_io_client.dart' as IO;

// import 'api.dart';
// import 'auth_store.dart';
// import 'login_page.dart';
// import 'socket_service.dart';

// class ThreadPage extends StatefulWidget {
//   final String peerId; // for history GET
//   final String partnerEmail; // for sending with toEmail
//   const ThreadPage({
//     super.key,
//     required this.peerId,
//     required this.partnerEmail,
//   });

//   @override
//   State<ThreadPage> createState() => _ThreadPageState();
// }

// class _ThreadPageState extends State<ThreadPage> {
//   final input = TextEditingController();
//   final items = <Map<String, dynamic>>[];
//   String? myId;

//   @override
//   void initState() {
//     super.initState();
//     _init();
//   }

//   Future<void> _init() async {
//     final u = await AuthStore.getUser();
//     if (u == null) return _logout();
//     myId = u['id'].toString();

//     await _loadHistory();

//     // listen realtime
//     SocketService.I.on('message', _onMessage);
//   }

//   void _onMessage(dynamic data) {
//     final m = Map<String, dynamic>.from(data);
//     final hit =
//         (m['from'].toString() == widget.peerId && m['to'].toString() == myId) ||
//         (m['to'].toString() == widget.peerId && m['from'].toString() == myId);
//     if (!hit) return;
//     if (!mounted) return;
//     setState(() => items.add(m));
//   }

//   Future<void> _loadHistory() async {
//     final r = await http.get(
//       Uri.parse('$apiBase/messages?userA=$myId&userB=${widget.peerId}'),
//       headers: await authHeaders(),
//     );
//     if (r.statusCode == 200) {
//       final list = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
//       setState(() {
//         items
//           ..clear()
//           ..addAll(list);
//       });
//     }
//   }

//   Future<void> _send() async {
//     final text = input.text.trim();
//     if (text.isEmpty) return;
//     input.clear();

//     // optimistic append
//     final temp = {
//       '_id': 'local-${DateTime.now().microsecondsSinceEpoch}',
//       'from': myId,
//       'to': widget.peerId,
//       'text': text,
//       'createdAt': DateTime.now().toIso8601String(),
//     };
//     setState(() => items.add(temp));

//     final r = await postJson('/messages', {
//       'from': myId,
//       'toEmail': widget.partnerEmail, // email-based send
//       'text': text,
//     });

//     if (r.statusCode != 200) {
//       // revert on fail
//       setState(() => items.removeWhere((m) => m['_id'] == temp['_id']));
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text(
//             r.statusCode == 403
//                 ? 'Receiver has not accepted your request yet.'
//                 : r.statusCode == 404
//                 ? 'Recipient not found.'
//                 : 'Send failed (${r.statusCode})',
//           ),
//         ),
//       );
//     }
//     // success: server will echo 'message' to both -> UI updated by listener
//   }

//   Future<void> _logout() async {
//     await AuthStore.clear();
//     SocketService.I.disconnect();
//     if (!mounted) return;
//     Navigator.pushAndRemoveUntil(
//       context,
//       MaterialPageRoute(builder: (_) => const LoginPage()),
//       (_) => false,
//     );
//   }

//   @override
//   void dispose() {
//     input.dispose();
//     SocketService.I.off('message', _onMessage);
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final title = widget.partnerEmail;
//     return Scaffold(
//       appBar: AppBar(
//         title: Text(title),
//         actions: [
//           IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
//         ],
//       ),
//       body: Column(
//         children: [
//           Expanded(
//             child: ListView.builder(
//               padding: const EdgeInsets.all(12),
//               itemCount: items.length,
//               itemBuilder: (_, i) {
//                 final m = items[i];
//                 final mine = m['from'].toString() == myId;
//                 return Align(
//                   alignment: mine
//                       ? Alignment.centerRight
//                       : Alignment.centerLeft,
//                   child: Container(
//                     margin: const EdgeInsets.symmetric(vertical: 4),
//                     padding: const EdgeInsets.all(10),
//                     decoration: BoxDecoration(
//                       color: mine
//                           ? Colors.blue.withOpacity(.15)
//                           : Colors.grey.withOpacity(.2),
//                       borderRadius: BorderRadius.circular(10),
//                     ),
//                     child: Text(m['text'] ?? ''),
//                   ),
//                 );
//               },
//             ),
//           ),
//           SafeArea(
//             top: false,
//             child: Row(
//               children: [
//                 Expanded(
//                   child: Padding(
//                     padding: const EdgeInsets.all(8.0),
//                     child: TextField(
//                       controller: input,
//                       onSubmitted: (_) => _send(),
//                       decoration: const InputDecoration(
//                         hintText: 'Type a message...',
//                       ),
//                     ),
//                   ),
//                 ),
//                 IconButton(icon: const Icon(Icons.send), onPressed: _send),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
