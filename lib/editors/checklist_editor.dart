import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gitjournal/core/checklist.dart';

import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/editors/common.dart';
import 'package:gitjournal/editors/note_title_editor.dart';

class ChecklistEditor extends StatefulWidget implements Editor {
  final Note note;

  @override
  final NoteCallback noteDeletionSelected;
  @override
  final NoteCallback noteEditorChooserSelected;
  @override
  final NoteCallback exitEditorSelected;
  @override
  final NoteCallback renameNoteSelected;
  @override
  final NoteCallback moveNoteToFolderSelected;
  @override
  final NoteCallback discardChangesSelected;

  final bool autofocusOnEditor;

  ChecklistEditor({
    Key key,
    @required this.note,
    @required this.noteDeletionSelected,
    @required this.noteEditorChooserSelected,
    @required this.exitEditorSelected,
    @required this.renameNoteSelected,
    @required this.moveNoteToFolderSelected,
    @required this.discardChangesSelected,
    @required this.autofocusOnEditor,
  }) : super(key: key);

  @override
  ChecklistEditorState createState() {
    return ChecklistEditorState(note);
  }
}

class ChecklistEditorState extends State<ChecklistEditor>
    implements EditorState {
  Checklist checklist;
  var focusNodes = <ChecklistItem, FocusScopeNode>{};
  TextEditingController _titleTextController = TextEditingController();

  ChecklistEditorState(Note note) {
    _titleTextController = TextEditingController(text: note.title);
    checklist = Checklist(note);
  }

  @override
  void initState() {
    super.initState();
    if (checklist.items.isEmpty) {
      var item = checklist.buildItem(false, "");
      checklist.addItem(item);
    }

    for (var item in checklist.items) {
      focusNodes[item] = FocusScopeNode();
    }
  }

  @override
  void dispose() {
    _titleTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var itemTiles = <Widget>[];
    for (var i = 0; i < checklist.items.length; i++) {
      var item = checklist.items[i];
      var autofocus =
          widget.autofocusOnEditor && (i == checklist.items.length - 1);
      itemTiles.add(_buildTile(item, i, autofocus));
    }
    itemTiles.add(AddItemButton(
      key: UniqueKey(),
      onPressed: () {
        setState(() {
          var fn = FocusScopeNode();
          var item = checklist.buildItem(false, "");
          checklist.addItem(item);
          focusNodes[item] = fn;

          // FIXME: Make this happen on the next build
          Timer(const Duration(milliseconds: 50), () {
            FocusScope.of(context).requestFocus(fn);
          });
        });
      },
    ));

    Widget checklistWidget = ReorderableListView(
      children: itemTiles,
      onReorder: (int oldIndex, int newIndex) {
        setState(() {
          var item = checklist.removeAt(oldIndex);

          if (newIndex > oldIndex) {
            checklist.insertItem(newIndex - 1, item);
          } else {
            checklist.insertItem(newIndex, item);
          }
        });
      },
    );

    var titleEditor = Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0.0),
      child: NoteTitleEditor(_titleTextController),
    );

    return Scaffold(
      appBar: buildEditorAppBar(widget, this),
      body: Column(
        children: <Widget>[
          if (widget.note.canHaveMetadata) titleEditor,
          Expanded(child: FocusScope(child: checklistWidget)),
        ],
      ),
    );
  }

  @override
  Note getNote() {
    var note = checklist.note;
    note.title = _titleTextController.text.trim();
    note.type = NoteType.Checklist;
    return note;
  }

  ChecklistItemTile _buildTile(ChecklistItem item, int index, bool autofocus) {
    return ChecklistItemTile(
      key: UniqueKey(),
      item: item,
      focusNode: focusNodes[item],
      autofocus: autofocus,
      statusChanged: (bool newVal) {
        setState(() {
          item.checked = newVal;
        });
      },
      textChanged: (String newVal) {
        item.text = newVal;
      },
      itemRemoved: () {
        setState(() {
          // Give next item the focus
          var nextIndex = index + 1;
          if (index >= checklist.items.length - 1) {
            nextIndex = index - 1;
          }
          print("Next focus index $nextIndex");

          FocusNode fn;
          if (nextIndex >= 0) {
            var nextItemForFocus = checklist.items[nextIndex];
            fn = focusNodes[nextItemForFocus];
            print("Giving focus to $nextItemForFocus");
          }

          focusNodes.remove(item);
          checklist.removeItem(item);

          // FIXME: Make this happen on the next build
          Timer(const Duration(milliseconds: 300), () {
            if (fn != null) {
              FocusScope.of(context).requestFocus(fn);
            }
          });
        });
      },
      itemFinished: () {
        setState(() {
          var fn = FocusScopeNode();
          var item = checklist.buildItem(false, "");
          checklist.insertItem(index + 1, item);
          focusNodes[item] = fn;

          // FIXME: Make this happen on the next build
          Timer(const Duration(milliseconds: 50), () {
            print("Asking focus to ${index + 1}");
            FocusScope.of(context).requestFocus(fn);
          });
        });
      },
    );
  }
}

typedef TextChangedFunction = void Function(String);
typedef StatusChangedFunction = void Function(bool);

class ChecklistItemTile extends StatefulWidget {
  final ChecklistItem item;
  final StatusChangedFunction statusChanged;
  final TextChangedFunction textChanged;
  final Function itemRemoved;
  final Function itemFinished;
  final FocusNode focusNode;
  final bool autofocus;

  ChecklistItemTile({
    Key key,
    @required this.item,
    @required this.statusChanged,
    @required this.textChanged,
    @required this.itemRemoved,
    @required this.itemFinished,
    @required this.focusNode,
    this.autofocus = false,
  }) : super(key: key);

  @override
  _ChecklistItemTileState createState() => _ChecklistItemTileState();
}

class _ChecklistItemTileState extends State<ChecklistItemTile> {
  TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.item.text);
    _textController.addListener(() {
      widget.textChanged(_textController.value.text);
    });
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    _textController.dispose();
    widget.focusNode.removeListener(_onFocus);

    super.dispose();
  }

  void _onFocus() {
    setState(() {}); // rebuild to hide close button
    SystemChannels.textInput.invokeMethod('TextInput.show');
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var style = theme.textTheme.subhead;
    if (widget.item.checked) {
      style = style.copyWith(
        decoration: TextDecoration.lineThrough,
        color: theme.disabledColor,
      );
    }

    var editor = TextField(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      keyboardType: TextInputType.text,
      maxLines: null,
      style: style,
      textCapitalization: TextCapitalization.sentences,
      controller: _textController,
      decoration: const InputDecoration(
        border: InputBorder.none,
        isDense: true,
      ),
      onEditingComplete: widget.itemFinished,
    );

    return ListTile(
      dense: true,
      leading: Row(
        children: <Widget>[
          Container(height: 24.0, width: 24.0, child: Icon(Icons.drag_handle)),
          const SizedBox(width: 8.0),
          SizedBox(
            height: 24.0,
            width: 24.0,
            child: Checkbox(
              value: widget.item.checked,
              onChanged: widget.statusChanged,
            ),
          ),
        ],
        mainAxisSize: MainAxisSize.min,
      ),
      title: editor,
      trailing: IconButton(
        icon: Icon(widget.focusNode.hasFocus ? Icons.clear : null),
        onPressed: widget.itemRemoved,
      ),
      enabled: !widget.item.checked,
    );
  }
}

class AddItemButton extends StatelessWidget {
  final Function onPressed;

  AddItemButton({Key key, @required this.onPressed}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var style = Theme.of(context).textTheme.subhead;

    return ListTile(
      dense: true,
      leading: Row(
        children: <Widget>[
          Container(height: 24.0, width: 24.0),
          const SizedBox(width: 8.0),
          Container(
            padding: const EdgeInsets.all(0.0),
            width: 24.0,
            child: IconButton(
              padding: const EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
              icon: Icon(Icons.add),
              onPressed: onPressed,
            ),
          ),
        ],
        mainAxisSize: MainAxisSize.min,
      ),
      title: GestureDetector(
        onTap: onPressed,
        child: Text("Add Item", style: style),
      ),
    );
  }
}

// FIXME: The body needs to be scrollable
// FIXME: Support removing an item when pressing backspace
// FIXME: Align the checkbox and close button on top
// FIXME: Move checked items to the bottom?
