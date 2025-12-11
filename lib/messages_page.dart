// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:socket_io_client/socket_io_client.dart' as IO;
// import 'package:http/http.dart' as http;

// import 'api.dart';
// import 'auth_store.dart';
// import 'login_page.dart' hide apiBase;
// import 'notifications.dart';

// class MessagesPage extends StatefulWidget {
//   final String partnerId; // history ဆွဲရန် (GET /messages?userA&userB)
//   final String partnerEmail; // ပို့ရန် (POST /messages with toEmail)
//   const MessagesPage({
//     super.key,
//     required this.partnerId,
//     required this.partnerEmail,
//   });

//   @override
//   State<MessagesPage> createState() => _MessagesPageState();
// }

// class _MessagesPageState extends State<MessagesPage> {
//   IO.Socket? socket;
//   final input = TextEditingController();
//   final items = <Map<String, dynamic>>[];
//   String? myId;

//   @override
//   void initState() {
//     super.initState();
//     _init();
//   }

//   Future<void> _init() async {
//     final u = await AuthStore.user();
//     final t = await AuthStore.token();
//     if (u == null || t == null) return;
//     myId = u['id'];

//     await initLocalNoti();
//     await _loadHistory();
//     await _connect(t);
//   }

//   Future<void> _connect(String token) async {
//     socket = IO.io(
//       apiBase,
//       IO.OptionBuilder()
//           .setTransports(['websocket'])
//           .setAuth({'token': token})
//           .disableAutoConnect()
//           .build(),
//     );

//     socket!.on('message', (data) async {
//       final m = Map<String, dynamic>.from(data);
//       // current chat only
//       if ((m['from'] == widget.partnerId && m['to'] == myId) ||
//           (m['to'] == widget.partnerId && m['from'] == myId)) {
//         setState(() => items.add(m));
//       }
//       if (m['to'] == myId) {
//         await showMessageNoti(
//           title: widget.partnerEmail,
//           body: m['text']?.toString() ?? '',
//         );
//       }
//     });

//     socket!.connect();
//   }

//   Future<void> _loadHistory() async {
//     final r = await http.get(
//       Uri.parse('$apiBase/messages?userA=$myId&userB=${widget.partnerId}'),
//       headers: await authHeaders(),
//     );
//     if (r.statusCode == 200) {
//       final list = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
//       setState(
//         () => items
//           ..clear()
//           ..addAll(list),
//       );
//     }
//   }

//   Future<void> _send() async {
//     final text = input.text.trim();
//     if (text.isEmpty) return;
//     input.clear();

//     final r = await postJson('/messages', {
//       'from': myId,
//       'toEmail': widget.partnerEmail, // <- email သုံးပြီး ပို့
//       'text': text,
//     });

//     if (r.statusCode == 403) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Receiver has not accepted your request yet.'),
//         ),
//       );
//     } else if (r.statusCode == 404) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Recipient email not found.')),
//       );
//     }
//     // 200 OK ဖြစ်ရင် socket က receiver ဆီ emit လုပ်ပေးနေမှာ -> sender UI ကိုလည်း
//     // backend ထဲမှာ emit မလာတဲ့အခါ list refresh လုပ်ချင်ရင် _loadHistory() ခေါ်ပါ
//   }

//   Future<void> _logout() async {
//     await AuthStore.clear();
//     socket?.dispose();
//     if (!mounted) return;
//     Navigator.pushAndRemoveUntil(
//       context,
//       MaterialPageRoute(builder: (_) => const LoginPage()),
//       (_) => false,
//     );
//   }

//   @override
//   void dispose() {
//     socket?.dispose();
//     input.dispose();
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
//                 final mine = m['from'] == myId;
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
