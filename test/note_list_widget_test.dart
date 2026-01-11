import 'package:cogniread/src/features/library/data/library_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoteListWidget extends StatefulWidget {
  const _NoteListWidget({required this.notes});

  final ValueNotifier<List<Note>> notes;

  @override
  State<_NoteListWidget> createState() => _NoteListWidgetState();
}

class _NoteListWidgetState extends State<_NoteListWidget> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<List<Note>>(
          valueListenable: widget.notes,
          builder: (context, notes, _) {
            return Column(
              children: [
                FilledButton(
                  key: const ValueKey('add-note'),
                  onPressed: () {
                    widget.notes.value = [
                      ...notes,
                      Note(
                        id: 'note-1',
                        bookId: 'book-1',
                        anchor: null,
                        endOffset: null,
                        excerpt: 'Excerpt',
                        noteText: 'Test note',
                        color: 'yellow',
                        createdAt: DateTime(2026, 1, 11, 10),
                        updatedAt: DateTime(2026, 1, 11, 10),
                      ),
                    ];
                  },
                  child: const Text('Add note'),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final note in notes)
                        ListTile(title: Text(note.noteText)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

void main() {
  testWidgets('Create note shows in list', (tester) async {
    final notes = ValueNotifier<List<Note>>(<Note>[]);

    await tester.pumpWidget(_NoteListWidget(notes: notes));
    expect(find.text('Test note'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('add-note')));
    await tester.pump();

    expect(find.text('Test note'), findsOneWidget);
  });
}
