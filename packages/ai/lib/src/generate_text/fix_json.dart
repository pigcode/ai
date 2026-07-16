enum _FixJsonState {
  root,
  finish,
  insideString,
  insideStringEscape,
  insideStringUnicodeEscape,
  insideLiteral,
  insideNumber,
  insideObjectStart,
  insideObjectKey,
  insideObjectAfterKey,
  insideObjectBeforeValue,
  insideObjectAfterValue,
  insideObjectAfterComma,
  insideArrayStart,
  insideArrayAfterValue,
  insideArrayAfterComma,
}

/// Repairs a partial JSON string by closing open strings, objects, arrays, and
/// literals where the already-seen prefix is otherwise valid JSON.
String fixJson(String input) {
  final stack = <_FixJsonState>[_FixJsonState.root];
  var lastValidIndex = -1;
  int? literalStart;
  var unicodeEscapeDigits = 0;

  bool isHexDigit(String char) {
    return (char.compareTo('0') >= 0 && char.compareTo('9') <= 0) ||
        (char.compareTo('A') >= 0 && char.compareTo('F') <= 0) ||
        (char.compareTo('a') >= 0 && char.compareTo('f') <= 0);
  }

  void processValueStart(
    String char,
    int index,
    _FixJsonState swapState,
  ) {
    switch (char) {
      case '"':
        lastValidIndex = index;
        stack.removeLast();
        stack
          ..add(swapState)
          ..add(_FixJsonState.insideString);
      case 'f':
      case 't':
      case 'n':
        lastValidIndex = index;
        literalStart = index;
        stack.removeLast();
        stack
          ..add(swapState)
          ..add(_FixJsonState.insideLiteral);
      case '-':
        stack.removeLast();
        stack
          ..add(swapState)
          ..add(_FixJsonState.insideNumber);
      case '0':
      case '1':
      case '2':
      case '3':
      case '4':
      case '5':
      case '6':
      case '7':
      case '8':
      case '9':
        lastValidIndex = index;
        stack.removeLast();
        stack
          ..add(swapState)
          ..add(_FixJsonState.insideNumber);
      case '{':
        lastValidIndex = index;
        stack.removeLast();
        stack
          ..add(swapState)
          ..add(_FixJsonState.insideObjectStart);
      case '[':
        lastValidIndex = index;
        stack.removeLast();
        stack
          ..add(swapState)
          ..add(_FixJsonState.insideArrayStart);
    }
  }

  void processAfterObjectValue(String char, int index) {
    switch (char) {
      case ',':
        stack
          ..removeLast()
          ..add(_FixJsonState.insideObjectAfterComma);
      case '}':
        lastValidIndex = index;
        stack.removeLast();
    }
  }

  void processAfterArrayValue(String char, int index) {
    switch (char) {
      case ',':
        stack
          ..removeLast()
          ..add(_FixJsonState.insideArrayAfterComma);
      case ']':
        lastValidIndex = index;
        stack.removeLast();
    }
  }

  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    final currentState = stack.last;

    switch (currentState) {
      case _FixJsonState.root:
        processValueStart(char, i, _FixJsonState.finish);

      case _FixJsonState.insideObjectStart:
        switch (char) {
          case '"':
            stack
              ..removeLast()
              ..add(_FixJsonState.insideObjectKey);
          case '}':
            lastValidIndex = i;
            stack.removeLast();
        }

      case _FixJsonState.insideObjectAfterComma:
        switch (char) {
          case '"':
            stack
              ..removeLast()
              ..add(_FixJsonState.insideObjectKey);
        }

      case _FixJsonState.insideObjectKey:
        switch (char) {
          case '"':
            stack
              ..removeLast()
              ..add(_FixJsonState.insideObjectAfterKey);
        }

      case _FixJsonState.insideObjectAfterKey:
        switch (char) {
          case ':':
            stack
              ..removeLast()
              ..add(_FixJsonState.insideObjectBeforeValue);
        }

      case _FixJsonState.insideObjectBeforeValue:
        processValueStart(char, i, _FixJsonState.insideObjectAfterValue);

      case _FixJsonState.insideObjectAfterValue:
        processAfterObjectValue(char, i);

      case _FixJsonState.insideString:
        switch (char) {
          case '"':
            stack.removeLast();
            lastValidIndex = i;
          case r'\':
            stack.add(_FixJsonState.insideStringEscape);
          default:
            lastValidIndex = i;
        }

      case _FixJsonState.insideArrayStart:
        switch (char) {
          case ']':
            lastValidIndex = i;
            stack.removeLast();
          default:
            lastValidIndex = i;
            processValueStart(char, i, _FixJsonState.insideArrayAfterValue);
        }

      case _FixJsonState.insideArrayAfterValue:
        switch (char) {
          case ',':
            stack
              ..removeLast()
              ..add(_FixJsonState.insideArrayAfterComma);
          case ']':
            lastValidIndex = i;
            stack.removeLast();
          default:
            lastValidIndex = i;
        }

      case _FixJsonState.insideArrayAfterComma:
        processValueStart(char, i, _FixJsonState.insideArrayAfterValue);

      case _FixJsonState.insideStringEscape:
        stack.removeLast();

        if (char == 'u') {
          unicodeEscapeDigits = 0;
          stack.add(_FixJsonState.insideStringUnicodeEscape);
        } else {
          lastValidIndex = i;
        }

      case _FixJsonState.insideStringUnicodeEscape:
        if (isHexDigit(char)) {
          unicodeEscapeDigits++;

          if (unicodeEscapeDigits == 4) {
            stack.removeLast();
            lastValidIndex = i;
          }
        }

      case _FixJsonState.insideNumber:
        switch (char) {
          case '0':
          case '1':
          case '2':
          case '3':
          case '4':
          case '5':
          case '6':
          case '7':
          case '8':
          case '9':
            lastValidIndex = i;
          case 'e':
          case 'E':
          case '-':
          case '.':
            break;
          case ',':
            stack.removeLast();

            if (stack.last == _FixJsonState.insideArrayAfterValue) {
              processAfterArrayValue(char, i);
            }

            if (stack.last == _FixJsonState.insideObjectAfterValue) {
              processAfterObjectValue(char, i);
            }
          case '}':
            stack.removeLast();

            if (stack.last == _FixJsonState.insideObjectAfterValue) {
              processAfterObjectValue(char, i);
            }
          case ']':
            stack.removeLast();

            if (stack.last == _FixJsonState.insideArrayAfterValue) {
              processAfterArrayValue(char, i);
            }
          default:
            stack.removeLast();
        }

      case _FixJsonState.insideLiteral:
        final partialLiteral = input.substring(literalStart!, i + 1);

        if (!'false'.startsWith(partialLiteral) &&
            !'true'.startsWith(partialLiteral) &&
            !'null'.startsWith(partialLiteral)) {
          stack.removeLast();

          if (stack.last == _FixJsonState.insideObjectAfterValue) {
            processAfterObjectValue(char, i);
          } else if (stack.last == _FixJsonState.insideArrayAfterValue) {
            processAfterArrayValue(char, i);
          }
        } else {
          lastValidIndex = i;
        }

      case _FixJsonState.finish:
        break;
    }
  }

  final buffer = StringBuffer(input.substring(0, lastValidIndex + 1));

  for (var i = stack.length - 1; i >= 0; i--) {
    final state = stack[i];

    switch (state) {
      case _FixJsonState.insideString:
        buffer.write('"');

      case _FixJsonState.insideObjectKey:
      case _FixJsonState.insideObjectAfterKey:
      case _FixJsonState.insideObjectAfterComma:
      case _FixJsonState.insideObjectStart:
      case _FixJsonState.insideObjectBeforeValue:
      case _FixJsonState.insideObjectAfterValue:
        buffer.write('}');

      case _FixJsonState.insideArrayStart:
      case _FixJsonState.insideArrayAfterComma:
      case _FixJsonState.insideArrayAfterValue:
        buffer.write(']');

      case _FixJsonState.insideLiteral:
        final partialLiteral = input.substring(literalStart!, input.length);

        if ('true'.startsWith(partialLiteral)) {
          buffer.write('true'.substring(partialLiteral.length));
        } else if ('false'.startsWith(partialLiteral)) {
          buffer.write('false'.substring(partialLiteral.length));
        } else if ('null'.startsWith(partialLiteral)) {
          buffer.write('null'.substring(partialLiteral.length));
        }

      case _FixJsonState.root:
      case _FixJsonState.finish:
      case _FixJsonState.insideStringEscape:
      case _FixJsonState.insideStringUnicodeEscape:
      case _FixJsonState.insideNumber:
        break;
    }
  }

  return buffer.toString();
}
