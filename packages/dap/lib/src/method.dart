import 'generated/dap_inventory.g.dart';

final class DapRequestDescriptor {
  const DapRequestDescriptor({
    required this.command,
    required this.requestDefinition,
    required this.responseDefinition,
    required this.argumentsDefinition,
  });

  final String command;
  final String requestDefinition;
  final String responseDefinition;
  final String? argumentsDefinition;
}

final class DapEventDescriptor {
  const DapEventDescriptor({
    required this.event,
    required this.definition,
  });

  final String event;
  final String definition;
}

final List<DapRequestDescriptor> dapRequestDescriptors =
    List<DapRequestDescriptor>.unmodifiable(
  dapGeneratedRequestMetadata.map(
    (metadata) => DapRequestDescriptor(
      command: metadata['command']!,
      requestDefinition: metadata['request']!,
      responseDefinition: metadata['response']!,
      argumentsDefinition: metadata['arguments'],
    ),
  ),
);

final List<DapEventDescriptor> dapEventDescriptors =
    List<DapEventDescriptor>.unmodifiable(
  dapGeneratedEventMetadata.map(
    (metadata) => DapEventDescriptor(
      event: metadata['event']!,
      definition: metadata['definition']!,
    ),
  ),
);

final Map<String, DapRequestDescriptor> dapRequestsByCommand =
    Map<String, DapRequestDescriptor>.unmodifiable(
  <String, DapRequestDescriptor>{
    for (final descriptor in dapRequestDescriptors)
      descriptor.command: descriptor,
  },
);

final Map<String, DapEventDescriptor> dapEventsByName =
    Map<String, DapEventDescriptor>.unmodifiable(
  <String, DapEventDescriptor>{
    for (final descriptor in dapEventDescriptors) descriptor.event: descriptor,
  },
);

const dapClosedEnumCount = dapGeneratedClosedEnumCount;
const dapOpenEnumCount = dapGeneratedOpenEnumCount;
