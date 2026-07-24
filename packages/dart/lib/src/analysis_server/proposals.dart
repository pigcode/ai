import 'dart:async';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../common/errors.dart';

sealed class AnalysisServerEditProposal {
  const AnalysisServerEditProposal(this.value);

  final JsonObject value;

  JsonObject toJson() => value;
}

final class AnalysisServerSourcePosition {
  AnalysisServerSourcePosition._(this.value);

  factory AnalysisServerSourcePosition.fromJson(
    Map<String, Object?> value,
  ) {
    final file = value['file'];
    final offset = value['offset'];
    if (file is! String || file.isEmpty || offset is! int || offset < 0) {
      throw const ToolingProposalError(
        'analysis_server_source_position_invalid',
        'Analysis Server source position requires a file and non-negative offset.',
      );
    }
    return AnalysisServerSourcePosition._(freezeJsonObject(value));
  }

  final JsonObject value;

  String get file => value['file']! as String;
  int get offset => value['offset']! as int;
}

final class AnalysisServerSourceEdit {
  AnalysisServerSourceEdit._(this.value);

  factory AnalysisServerSourceEdit.fromJson(Map<String, Object?> value) {
    final offset = value['offset'];
    final length = value['length'];
    final replacement = value['replacement'];
    final id = value['id'];
    final description = value['description'];
    if (offset is! int ||
        offset < 0 ||
        length is! int ||
        length < 0 ||
        replacement is! String ||
        id != null && id is! String ||
        description != null && description is! String) {
      throw const ToolingProposalError(
        'analysis_server_source_edit_invalid',
        'Analysis Server source edit is malformed.',
      );
    }
    if (replacement.length > _maxReplacementLength) {
      throw const ToolingResourceLimitError(
        'analysis_server_source_edit_too_large',
        'Analysis Server source edit replacement exceeds its limit.',
      );
    }
    return AnalysisServerSourceEdit._(freezeJsonObject(value));
  }

  final JsonObject value;

  int get offset => value['offset']! as int;
  int get length => value['length']! as int;
  String get replacement => value['replacement']! as String;
  String? get id => value['id'] as String?;
  String? get description => value['description'] as String?;
}

final class AnalysisServerSourceFileEdit extends AnalysisServerEditProposal {
  AnalysisServerSourceFileEdit._(
    super.value, {
    required this.edits,
  });

  factory AnalysisServerSourceFileEdit.fromJson(Map<String, Object?> value) {
    final file = value['file'];
    final fileStamp = value['fileStamp'];
    final rawEdits = value['edits'];
    if (file is! String ||
        file.isEmpty ||
        fileStamp is! int ||
        rawEdits is! List<Object?> ||
        rawEdits.length > _maxEditsPerFile) {
      throw const ToolingProposalError(
        'analysis_server_source_file_edit_invalid',
        'Analysis Server source file edit is malformed or too large.',
      );
    }
    final edits = <AnalysisServerSourceEdit>[];
    for (final rawEdit in rawEdits) {
      if (rawEdit is! Map<String, Object?>) {
        throw const ToolingProposalError(
          'analysis_server_source_edit_invalid',
          'Analysis Server source edit must be an object.',
        );
      }
      edits.add(AnalysisServerSourceEdit.fromJson(rawEdit));
    }
    return AnalysisServerSourceFileEdit._(
      freezeJsonObject(value),
      edits: List<AnalysisServerSourceEdit>.unmodifiable(edits),
    );
  }

  final List<AnalysisServerSourceEdit> edits;

  String get file => value['file']! as String;
  int get fileStamp => value['fileStamp']! as int;
}

final class AnalysisServerSourceChangeProposal
    extends AnalysisServerEditProposal {
  AnalysisServerSourceChangeProposal._(
    super.value, {
    required this.edits,
    required this.selection,
  });

  factory AnalysisServerSourceChangeProposal.fromJson(
    Map<String, Object?> value,
  ) {
    final message = value['message'];
    final rawEdits = value['edits'];
    final rawGroups = value['linkedEditGroups'];
    final rawSelection = value['selection'];
    final selectionLength = value['selectionLength'];
    if (message is! String ||
        rawEdits is! List<Object?> ||
        rawEdits.length > _maxChangedFiles ||
        rawGroups is! List<Object?> ||
        rawGroups.length > _maxLinkedEditGroups ||
        rawGroups.any((group) => group is! Map<String, Object?>) ||
        rawSelection != null && rawSelection is! Map<String, Object?> ||
        selectionLength != null &&
            (selectionLength is! int || selectionLength < 0)) {
      throw const ToolingProposalError(
        'analysis_server_source_change_invalid',
        'Analysis Server SourceChange is malformed or too large.',
      );
    }
    final edits = <AnalysisServerSourceFileEdit>[];
    var totalEdits = 0;
    var totalReplacementLength = 0;
    for (final rawEdit in rawEdits) {
      if (rawEdit is! Map<String, Object?>) {
        throw const ToolingProposalError(
          'analysis_server_source_file_edit_invalid',
          'Analysis Server source file edit must be an object.',
        );
      }
      final edit = AnalysisServerSourceFileEdit.fromJson(rawEdit);
      totalEdits += edit.edits.length;
      totalReplacementLength += edit.edits.fold<int>(
        0,
        (length, sourceEdit) => length + sourceEdit.replacement.length,
      );
      if (totalEdits > _maxTotalEdits) {
        throw const ToolingResourceLimitError(
          'analysis_server_source_change_too_large',
          'Analysis Server SourceChange contains too many edits.',
        );
      }
      if (totalReplacementLength > _maxTotalReplacementLength) {
        throw const ToolingResourceLimitError(
          'analysis_server_source_change_too_large',
          'Analysis Server SourceChange replacement text exceeds its limit.',
        );
      }
      edits.add(edit);
    }
    return AnalysisServerSourceChangeProposal._(
      freezeJsonObject(value),
      edits: List<AnalysisServerSourceFileEdit>.unmodifiable(edits),
      selection: rawSelection == null
          ? null
          : AnalysisServerSourcePosition.fromJson(
              rawSelection as Map<String, Object?>,
            ),
    );
  }

  final List<AnalysisServerSourceFileEdit> edits;
  final AnalysisServerSourcePosition? selection;

  String get message => value['message']! as String;
  int? get selectionLength => value['selectionLength'] as int?;
  List<JsonObject> get linkedEditGroups => List<JsonObject>.unmodifiable(
        (value['linkedEditGroups']! as List<Object?>).cast<JsonObject>(),
      );
}

typedef AnalysisServerEditProposalHandler = FutureOr<JsonValue> Function(
  AnalysisServerEditProposal proposal,
);

/// Dispatches edits only to a handler explicitly installed by the caller.
final class AnalysisServerEditProposalDispatcher {
  AnalysisServerEditProposalHandler? _handler;

  void register(AnalysisServerEditProposalHandler handler) {
    if (_handler != null) {
      throw const ToolingProposalError(
        'analysis_server_edit_handler_duplicate',
        'Analysis Server edit proposal handler is already registered.',
      );
    }
    _handler = handler;
  }

  FutureOr<JsonValue> dispatchSourceChange(Map<String, Object?> value) {
    return _dispatch(AnalysisServerSourceChangeProposal.fromJson(value));
  }

  FutureOr<JsonValue> dispatchSourceFileEdit(Map<String, Object?> value) {
    return _dispatch(AnalysisServerSourceFileEdit.fromJson(value));
  }

  FutureOr<JsonValue> _dispatch(AnalysisServerEditProposal proposal) {
    final handler = _handler;
    if (handler == null) {
      throw const ToolingProposalError(
        'analysis_server_edit_handler_missing',
        'No caller handler accepts this Analysis Server edit proposal.',
      );
    }
    return handler(proposal);
  }
}

const _maxChangedFiles = 4096;
const _maxEditsPerFile = 65536;
const _maxTotalEdits = 262144;
const _maxLinkedEditGroups = 65536;
const _maxReplacementLength = 8 * 1024 * 1024;
const _maxTotalReplacementLength = 64 * 1024 * 1024;
