/// 事件库头文件。
///
/// Dart 的 `sealed` 要求所有子类型与声明位于**同一 library**(而非同一文件)。
/// [LanguageModelContent] 与 [LanguageModelStreamPart] 复用一批「内容项」,故两个
/// sealed 根、7 个共用内容项、仅 content 的 Text/Reasoning 与全部流专属分块必须
/// 同库。这里用一个库头加两个 part 文件聚合它们,既满足同库约束,又让文件聚焦。
library;

import 'package:equatable/equatable.dart';

import 'finish_reason.dart';
import '../shared/shared.dart';
import 'usage.dart';

part 'content.dart';
part 'stream_part.dart';

/// doGenerate 输出侧的有序内容项根类型。
///
/// 其成员在 [content.dart] 中定义;其中 7 个「内容项」同时实现
/// [LanguageModelStreamPart](`TextContent`/`ReasoningContent` 仅 content),
/// 忠实映射「content 与 stream 复用同一批命名类型」。
sealed class LanguageModelContent {
  /// 常量基构造器,供所有内容项子类型 `const` 构造。
  const LanguageModelContent();
}

/// doStream 全量分块的根类型。
///
/// 其成员 = [content.dart] 中 **7 个**共用内容项(不含 `TextContent`/
/// `ReasoningContent`,二者仅 content;流侧文本/推理走 id 关联的 delta 事件) +
/// [stream_part.dart] 的流专属分块。契约层坚持 error-as-event(不把流错误转成
/// 抛异常),且按 **error 即终端事件** 模型:[ErrorPart] 一旦发出即视为流结束,
/// 其后不应再有任何分块。
sealed class LanguageModelStreamPart {}
