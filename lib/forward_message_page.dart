// lib/forward_message_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_contacts/flutter_contacts.dart';
import 'api.dart';
import 'auth_store.dart';
import 'chat_page.dart';
import 'widgets/avatar_with_status.dart';

class ForwardMessagePage extends StatefulWidget {
  final Map<String, dynamic> message;

  const ForwardMessagePage({
    super.key,
    required this.message,
  });

  @override
  State<ForwardMessagePage> createState() => _ForwardMessagePageState();
}

class _ForwardMessagePageState extends State<ForwardMessagePage> {
  List<Map<String, dynamic>> _allContacts = [];
  List<Map<String, dynamic>> _chatConversations = [];
  List<Map<String, dynamic>> _contactFriends = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  int _selectedTab = 0; // 0 = Chats, 1 = Contacts

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final me = await AuthStore.getUser();
      if (me == null) {
        setState(() {
          _error = 'Not authenticated';
          _loading = false;
        });
        return;
      }

      final myId = me['id'].toString();
      final allContacts = <Map<String, dynamic>>[];
      final chatConversations = <Map<String, dynamic>>[];
      final contactFriends = <Map<String, dynamic>>[];
      final contactIds = <String>{};

      // Load device contacts and sync to get all contact friends (Telegram-style)
      try {
        final hasPermission = await FlutterContacts.requestPermission();
        if (hasPermission) {
          final deviceContacts = await FlutterContacts.getContacts(
            withProperties: true,
            withThumbnail: false,
          );

          final contactList = deviceContacts
              .where((c) => c.phones.isNotEmpty)
              .map((c) {
                final phone = c.phones.first.number;
                return {
                  'phone': phone,
                  'name': c.name.first,
                };
              })
              .toList();

            if (contactList.isNotEmpty) {
            final token = await AuthStore.getToken();
            final contactsRes = await http.post(
              Uri.parse('${apiBase}/api/conversations/contacts/sync'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({'contacts': contactList}),
            ).timeout(const Duration(seconds: 10));

            if (contactsRes.statusCode == 200) {
              final contactsData = jsonDecode(contactsRes.body) as Map<String, dynamic>;
              final matches = (contactsData['matches'] as List?)
                  ?.cast<Map<String, dynamic>>() ?? [];

              for (final match in matches) {
                final contactId = match['id']?.toString();
                if (contactId != null && contactId != myId) {
                  contactIds.add(contactId);
                  final matchEmail = match['email']?.toString();
                  final matchPhone = match['phone']?.toString();
                  
                  // Try to find the original phone from contactList if not in match
                  String? phone = matchPhone;
                  if (phone == null || phone.isEmpty) {
                    // Find by matching email or name
                    try {
                      final found = contactList.firstWhere(
                        (c) {
                          final cPhone = c['phone']?.toString() ?? '';
                          final cName = c['name']?.toString() ?? '';
                          return matchEmail != null && matchEmail.isNotEmpty
                              ? (matchEmail.contains(cPhone) || cPhone.contains(matchEmail))
                              : (match['name']?.toString() == cName);
                        },
                        orElse: () => <String, String>{'phone': '', 'name': ''},
                      );
                      phone = found['phone']?.toString();
                    } catch (e) {
                      debugPrint('Could not find phone for contact: $e');
                    }
                  }
                  
                  final contactData = {
                    'peerId': contactId,
                    'email': matchEmail ?? contactId,
                    'name': match['name']?.toString() ?? matchEmail ?? contactId,
                    'phone': phone,
                    'isContact': true,
                  };
                  allContacts.add(contactData);
                  contactFriends.add(contactData);
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading device contacts: $e');
        // Continue even if contacts fail
      }

      // Load active conversations (for Chats tab) - this shows all active chat users
      try {
        final r = await getJson('/conversations?me=$myId&status=active')
            .timeout(const Duration(seconds: 10));

        if (r.statusCode == 200) {
          final list = (jsonDecode(r.body) as List)
              .cast<Map<String, dynamic>>();

          for (final it in list) {
            final parts = (it['participants'] as List)
                .map((e) => e.toString())
                .toList();
            final other = parts.firstWhere((x) => x != myId, orElse: () => myId);
            
            if (other != myId) {
              contactIds.add(other);
              
              // Create conversation entry (only for Chats tab)
              final conversationData = {
                'conversationId': it['_id'].toString(),
                'peerId': other,
                'email': other,
                'name': other,
                'isContact': false,
                'phone': it['phone']?.toString(), // Store phone if available
              };
              
              // Check if this contact already exists in allContacts (from synced contacts)
              final existingIndex = allContacts.indexWhere(
                (c) => c['peerId']?.toString() == other,
              );
              
              if (existingIndex >= 0) {
                // Update existing contact with conversationId
                allContacts[existingIndex]['conversationId'] = it['_id'].toString();
                // Add to chatConversations (for Chats tab) - create a copy
                chatConversations.add(Map<String, dynamic>.from(allContacts[existingIndex]));
              } else {
                // New contact - add to both allContacts and chatConversations
                allContacts.add(conversationData);
                chatConversations.add(conversationData);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading active conversations: $e');
        // Continue even if conversations fail
      }

      // Load profiles for all contacts
      if (contactIds.isNotEmpty) {
        final profilesRes = await getJson(
          '/api/users/by-ids?ids=${contactIds.join(',')}',
        ).timeout(const Duration(seconds: 10));

        if (profilesRes.statusCode == 200) {
          final profilesMap = Map<String, dynamic>.from(
            jsonDecode(profilesRes.body),
          );

          // Update contacts with profile data
          for (final contact in allContacts) {
            final peerId = contact['peerId']?.toString();
            if (peerId != null) {
              final profile = profilesMap[peerId] as Map<String, dynamic>?;
              if (profile != null) {
                contact['email'] = profile['email']?.toString() ?? contact['email'];
                contact['name'] = profile['name']?.toString() ?? 
                    profile['email']?.toString() ?? 
                    contact['name'];
                contact['avatarUrl'] = profile['avatarUrl']?.toString();
                contact['online'] = profile['online'] == true;
                contact['phone'] = profile['phone']?.toString() ?? contact['phone'];
              }
            }
          }
          
          // Also update chatConversations and contactFriends with profile data
          for (final contact in chatConversations) {
            final peerId = contact['peerId']?.toString();
            if (peerId != null) {
              final profile = profilesMap[peerId] as Map<String, dynamic>?;
              if (profile != null) {
                contact['email'] = profile['email']?.toString() ?? contact['email'];
                contact['name'] = profile['name']?.toString() ?? 
                    profile['email']?.toString() ?? 
                    contact['name'];
                contact['avatarUrl'] = profile['avatarUrl']?.toString();
                contact['online'] = profile['online'] == true;
                contact['phone'] = profile['phone']?.toString() ?? contact['phone'];
              }
            }
          }
          
          for (final contact in contactFriends) {
            final peerId = contact['peerId']?.toString();
            if (peerId != null) {
              final profile = profilesMap[peerId] as Map<String, dynamic>?;
              if (profile != null) {
                contact['email'] = profile['email']?.toString() ?? contact['email'];
                contact['name'] = profile['name']?.toString() ?? 
                    profile['email']?.toString() ?? 
                    contact['name'];
                contact['avatarUrl'] = profile['avatarUrl']?.toString();
                contact['online'] = profile['online'] == true;
                contact['phone'] = profile['phone']?.toString() ?? contact['phone'];
              }
            }
          }
        }
      }

      // Sort by name
      allContacts.sort((a, b) {
        final nameA = (a['name']?.toString() ?? '').toLowerCase();
        final nameB = (b['name']?.toString() ?? '').toLowerCase();
        return nameA.compareTo(nameB);
      });

      chatConversations.sort((a, b) {
        final nameA = (a['name']?.toString() ?? '').toLowerCase();
        final nameB = (b['name']?.toString() ?? '').toLowerCase();
        return nameA.compareTo(nameB);
      });

      contactFriends.sort((a, b) {
        final nameA = (a['name']?.toString() ?? '').toLowerCase();
        final nameB = (b['name']?.toString() ?? '').toLowerCase();
        return nameA.compareTo(nameB);
      });

      setState(() {
        _allContacts = allContacts;
        _chatConversations = chatConversations;
        _contactFriends = contactFriends;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _forwardToConversation(Map<String, dynamic> conversation) async {
    try {
      final peerId = conversation['peerId']?.toString();
      final peerEmail = conversation['email']?.toString();
      final peerName = conversation['name']?.toString();
      final conversationId = conversation['conversationId']?.toString();
      final isContact = conversation['isContact'] == true;

      if (peerId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid conversation')),
        );
        return;
      }

      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Get phone number - try from conversation data first, then fetch from API
      String? phone = conversation['phone']?.toString();
      if (phone == null || phone.isEmpty) {
        // Try to get phone from user profile
        try {
          final profileRes = await getJson('/api/users/by-ids?ids=$peerId')
              .timeout(const Duration(seconds: 5));
          if (profileRes.statusCode == 200) {
            final profilesMap = Map<String, dynamic>.from(
              jsonDecode(profileRes.body),
            );
            final profile = profilesMap[peerId] as Map<String, dynamic>?;
            phone = profile?['phone']?.toString() ?? peerEmail;
          } else {
            phone = peerEmail; // Fallback to email
          }
        } catch (e) {
          debugPrint('Error fetching phone: $e');
          phone = peerEmail; // Fallback to email
        }
      }

      // If this is a contact without an active conversation, create a chat request first
      if (isContact && conversationId == null) {
        try {
          final me = await AuthStore.getUser();
          if (me != null) {
            final myId = me['id'].toString();
            final requestRes = await postJson('/api/conversations/chat-requests', {
              'from': myId,
              'toPhone': phone,
            }).timeout(const Duration(seconds: 5));
            
            if (requestRes.statusCode != 200 && requestRes.statusCode != 201) {
              if (!mounted) return;
              Navigator.pop(context); // Close loading dialog
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cannot forward: Chat request not created. Please start a conversation first.'),
                ),
              );
              return;
            }
          }
        } catch (e) {
          debugPrint('Error creating chat request: $e');
          // Continue anyway - maybe conversation already exists
        }
      }

      // Prepare message data for forwarding
      final messageText = widget.message['text']?.toString() ?? '';
      final fileUrl = widget.message['fileUrl']?.toString();
      final fileName = widget.message['fileName']?.toString();
      final fileType = widget.message['fileType']?.toString();
      final audioDuration = widget.message['audioDuration'] as int?;

      // Create forward indicator in text
      final forwardText = messageText.isNotEmpty
          ? messageText
          : (fileType == 'image'
              ? '📷 Photo'
              : fileType == 'video'
                  ? '🎥 Video'
                  : fileType == 'audio' || fileType == 'voice'
                      ? '🎤 Voice message'
                      : fileName != null
                          ? '📎 $fileName'
                          : 'Forwarded message');

      // Send message to the selected conversation/contact
      final me = await AuthStore.getUser();
      if (me == null) {
        if (!mounted) return;
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not authenticated')),
        );
        return;
      }

      final myId = me['id'].toString();
      final messageData = <String, dynamic>{
        'from': myId,
        'toPhone': phone,
        'text': forwardText,
        'forwarded': true,
        'forwardedFrom': widget.message['from']?.toString(),
        'forwardedMessageId': widget.message['_id']?.toString() ?? widget.message['id']?.toString(),
      };

      if (fileUrl != null) {
        messageData['fileUrl'] = fileUrl;
        messageData['fileName'] = fileName;
        messageData['fileType'] = fileType;
        if (audioDuration != null) {
          messageData['audioDuration'] = audioDuration.toString();
        }
      }

      final res = await postJson('/api/messages', messageData);

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (res.statusCode == 200) {
        // Success - navigate to the chat page
        Navigator.pop(context); // Close forward page
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatPage(
              peerId: peerId,
              partnerEmail: peerEmail ?? peerId,
              peerName: peerName,
            ),
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message forwarded')),
        );
      } else {
        final errorMsg = res.statusCode == 403
            ? 'Receiver has not accepted your request yet. Please wait for them to accept.'
            : res.statusCode == 404
                ? 'Recipient not found.'
                : 'Forward failed (${res.statusCode})';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog if still open
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  List<Map<String, dynamic>> get _filteredConversations {
    // Get the appropriate list based on selected tab
    final sourceList = _selectedTab == 0 ? _chatConversations : _contactFriends;
    
    if (_searchQuery.isEmpty) {
      return sourceList;
    }
    final query = _searchQuery.toLowerCase();
    return sourceList.where((conv) {
      final name = (conv['name']?.toString() ?? '').toLowerCase();
      final email = (conv['email']?.toString() ?? '').toLowerCase();
      return name.contains(query) || email.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenHeight = MediaQuery.of(context).size.height;
    
    return Container(
      height: screenHeight * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Header with Cancel, Forward, Select
          Container(
            color: theme.colorScheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
                const Text(
                  'Forward',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    // Select mode for multiple forwarding
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'Select',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Search bar
          Container(
            color: theme.colorScheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Center(
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.85,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TextField(
                      controller: _searchController,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black87,
                      ),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                    if (_searchController.text.isEmpty)
                      IgnorePointer(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search,
                              color: Colors.grey[400],
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Search',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Content area
          Expanded(
            child: Container(
              color: Colors.white,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_error!),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadConversations,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : _filteredConversations.isEmpty
                          ? Center(
                              child: Text(
                                _searchQuery.isEmpty
                                    ? (_selectedTab == 0
                                        ? 'No chats found'
                                        : 'No contacts found')
                                    : 'No ${_selectedTab == 0 ? 'chats' : 'contacts'} match your search',
                                style: const TextStyle(
                                  color: Colors.black87,
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _filteredConversations.length,
                              itemBuilder: (context, index) {
                                final conv = _filteredConversations[index];
                                final name = conv['name']?.toString() ?? 'Unknown';
                                final email = conv['email']?.toString() ?? '';
                                final avatarUrl = conv['avatarUrl']?.toString();
                                final online = conv['online'] == true;

                                return ListTile(
                                  leading: AvatarWithStatus(
                                    avatarUrl: avatarUrl,
                                    fallbackText: name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    isOnline: online,
                                    radius: 24,
                                  ),
                                  title: Text(
                                    name,
                                    style: const TextStyle(
                                      color: Colors.black87,
                                    ),
                                  ),
                                  subtitle: email.isNotEmpty && email != name
                                      ? Text(
                                          email,
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                          ),
                                        )
                                      : null,
                                  onTap: () => _forwardToConversation(conv),
                                );
                              },
                            ),
            ),
          ),
          // Bottom tabs (Chats / Contacts) with toggle switch
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
            ),
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final switchWidth = constraints.maxWidth * 0.6; // 60% of available width
                  final segmentWidth = (switchWidth - 4) / 2;
                  
                  return Container(
                    width: switchWidth,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Stack(
                      children: [
                        // Animated selected segment background
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          left: _selectedTab == 0 ? 2 : segmentWidth + 2,
                          top: 2,
                          bottom: 2,
                          width: segmentWidth,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[600],
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                        // Toggle buttons
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedTab = 0;
                                  });
                                },
                                child: Container(
                                  alignment: Alignment.center,
                                  child: const Text(
                                    'Chats',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedTab = 1;
                                  });
                                },
                                child: Container(
                                  alignment: Alignment.center,
                                  child: const Text(
                                    'Contacts',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
