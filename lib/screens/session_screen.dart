import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class SessionScreen extends StatefulWidget {
  // ... (existing code)
  @override
  _SessionScreenState createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final TextEditingController textController = TextEditingController();
  
  // ... (existing code)

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context); 
    // ... (existing code)

    return Scaffold(
      appBar: AppBar(
        title: Text('Session Screen'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // ... (existing code)

            TextField(
              controller: textController,
              decoration: InputDecoration(
                labelText: 'Session Name',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),
            
            ElevatedButton(
              onPressed: () async {
                final name = textController.text.trim();
                if (name.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Please enter a session name')),
                    );
                  }
                  return;
                }
                
                try {
                  await appState.createSession(name);
                  if (context.mounted) {
                    Navigator.pushReplacementNamed(context, '/main');
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error creating session: $e')),
                    );
                  }
                }
              },
              child: Text('Create Session'),
            ),
          ],
        ),
      ),
    );
  }
} 