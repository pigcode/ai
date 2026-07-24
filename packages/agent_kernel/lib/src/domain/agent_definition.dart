final class AgentDefinitionRef {
  const AgentDefinitionRef(this.value);

  final String value;

  Map<String, Object?> toJson() => <String, Object?>{'value': value};
}
