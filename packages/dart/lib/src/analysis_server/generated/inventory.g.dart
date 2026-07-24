// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: Dart Analysis Server API 1.38.0/1.40.1, format 1.

const analysisServerGeneratedInventoryJson = r'''{
  "formatVersion": 1,
  "minimum": {
    "release": "3.6.0",
    "revision": "ae7ca5199a0559db0ae60533e9cedd3ce0d6ab04",
    "apiVersion": "1.38.0",
    "specSha256": "839ffd353fe1804add14106d07c62992e1da0153d08ce9bc2ddfda60dd4fdc28"
  },
  "current": {
    "release": "3.12.2",
    "revision": "d684a576a6aa954ae107a03b2b4e1d61c3bebe93",
    "apiVersion": "1.40.1",
    "specSha256": "72931aaae9706d5ba6927ee019f95c8de013eec547ff52463f529153c87c3c22"
  },
  "minimumRequestNames": [
    "analysis.getErrors",
    "analysis.getHover",
    "analysis.getImportedElements",
    "analysis.getLibraryDependencies",
    "analysis.getNavigation",
    "analysis.getReachableSources",
    "analysis.getSignature",
    "analysis.reanalyze",
    "analysis.setAnalysisRoots",
    "analysis.setGeneralSubscriptions",
    "analysis.setPriorityFiles",
    "analysis.setSubscriptions",
    "analysis.updateContent",
    "analysis.updateOptions",
    "analytics.enable",
    "analytics.isEnabled",
    "analytics.sendEvent",
    "analytics.sendTiming",
    "completion.getSuggestionDetails2",
    "completion.getSuggestions2",
    "completion.registerLibraryPaths",
    "diagnostic.getDiagnostics",
    "diagnostic.getServerPort",
    "edit.bulkFixes",
    "edit.format",
    "edit.formatIfEnabled",
    "edit.getAssists",
    "edit.getAvailableRefactorings",
    "edit.getFixes",
    "edit.getPostfixCompletion",
    "edit.getRefactoring",
    "edit.getStatementCompletion",
    "edit.importElements",
    "edit.isPostfixCompletionApplicable",
    "edit.listPostfixCompletionTemplates",
    "edit.organizeDirectives",
    "edit.sortMembers",
    "execution.createContext",
    "execution.deleteContext",
    "execution.getSuggestions",
    "execution.mapUri",
    "execution.setSubscriptions",
    "flutter.getWidgetDescription",
    "flutter.setSubscriptions",
    "flutter.setWidgetPropertyValue",
    "lsp.handle",
    "search.findElementReferences",
    "search.findMemberDeclarations",
    "search.findMemberReferences",
    "search.findTopLevelDeclarations",
    "search.getElementDeclarations",
    "search.getTypeHierarchy",
    "server.cancelRequest",
    "server.getVersion",
    "server.openUrlRequest",
    "server.setClientCapabilities",
    "server.setSubscriptions",
    "server.showMessageRequest",
    "server.shutdown"
  ],
  "currentRequestNames": [
    "analysis.getErrors",
    "analysis.getHover",
    "analysis.getImportedElements",
    "analysis.getLibraryDependencies",
    "analysis.getNavigation",
    "analysis.getReachableSources",
    "analysis.getSignature",
    "analysis.reanalyze",
    "analysis.setAnalysisRoots",
    "analysis.setGeneralSubscriptions",
    "analysis.setPriorityFiles",
    "analysis.setSubscriptions",
    "analysis.updateContent",
    "analysis.updateOptions",
    "analytics.enable",
    "analytics.isEnabled",
    "analytics.sendEvent",
    "analytics.sendTiming",
    "completion.getSuggestionDetails2",
    "completion.getSuggestions2",
    "completion.registerLibraryPaths",
    "diagnostic.getDiagnostics",
    "diagnostic.getServerPort",
    "edit.bulkFixes",
    "edit.format",
    "edit.formatIfEnabled",
    "edit.getAssists",
    "edit.getAvailableRefactorings",
    "edit.getFixes",
    "edit.getPostfixCompletion",
    "edit.getRefactoring",
    "edit.getStatementCompletion",
    "edit.importElements",
    "edit.isPostfixCompletionApplicable",
    "edit.listPostfixCompletionTemplates",
    "edit.organizeDirectives",
    "edit.sortMembers",
    "execution.createContext",
    "execution.deleteContext",
    "execution.getSuggestions",
    "execution.mapUri",
    "execution.setSubscriptions",
    "flutter.getWidgetDescription",
    "flutter.setSubscriptions",
    "flutter.setWidgetPropertyValue",
    "lsp.handle",
    "search.findElementReferences",
    "search.findMemberDeclarations",
    "search.findMemberReferences",
    "search.findTopLevelDeclarations",
    "search.getElementDeclarations",
    "search.getTypeHierarchy",
    "server.cancelRequest",
    "server.getVersion",
    "server.openUrlRequest",
    "server.setClientCapabilities",
    "server.setSubscriptions",
    "server.showMessageRequest",
    "server.shutdown"
  ],
  "minimumNotificationNames": [
    "analysis.analyzedFiles",
    "analysis.closingLabels",
    "analysis.errors",
    "analysis.flushResults",
    "analysis.folding",
    "analysis.highlights",
    "analysis.implemented",
    "analysis.invalidate",
    "analysis.navigation",
    "analysis.occurrences",
    "analysis.outline",
    "analysis.overrides",
    "completion.existingImports",
    "execution.launchData",
    "flutter.outline",
    "lsp.notification",
    "search.results",
    "server.connected",
    "server.error",
    "server.log",
    "server.status"
  ],
  "currentNotificationNames": [
    "analysis.analyzedFiles",
    "analysis.closingLabels",
    "analysis.errors",
    "analysis.flushResults",
    "analysis.folding",
    "analysis.highlights",
    "analysis.implemented",
    "analysis.invalidate",
    "analysis.navigation",
    "analysis.occurrences",
    "analysis.outline",
    "analysis.overrides",
    "completion.existingImports",
    "execution.launchData",
    "flutter.outline",
    "lsp.notification",
    "search.results",
    "server.connected",
    "server.error",
    "server.log",
    "server.pluginError",
    "server.status"
  ],
  "currentOnlyNotificationNames": [
    "server.pluginError"
  ],
  "minimumOnlyNames": [],
  "requests": {
    "analysis.getErrors": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "errors": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "AnalysisError"
              }
            }
          }
        }
      }
    },
    "analysis.getHover": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "hovers": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "HoverInformation"
              }
            }
          }
        }
      }
    },
    "analysis.getImportedElements": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "length": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "elements": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "ImportedElements"
              }
            }
          }
        }
      }
    },
    "analysis.getLibraryDependencies": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": null,
      "result": {
        "kind": "object",
        "fields": {
          "libraries": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "FilePath"
              }
            }
          },
          "packageMap": {
            "required": true,
            "shape": {
              "kind": "map",
              "key": {
                "kind": "ref",
                "name": "String"
              },
              "value": {
                "kind": "map",
                "key": {
                  "kind": "ref",
                  "name": "String"
                },
                "value": {
                  "kind": "list",
                  "item": {
                    "kind": "ref",
                    "name": "FilePath"
                  }
                }
              }
            }
          }
        }
      }
    },
    "analysis.getNavigation": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "length": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "files": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "FilePath"
              }
            }
          },
          "regions": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "NavigationRegion"
              }
            }
          },
          "targets": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "NavigationTarget"
              }
            }
          }
        }
      }
    },
    "analysis.getReachableSources": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "sources": {
            "required": true,
            "shape": {
              "kind": "map",
              "key": {
                "kind": "ref",
                "name": "String"
              },
              "value": {
                "kind": "list",
                "item": {
                  "kind": "ref",
                  "name": "String"
                }
              }
            }
          }
        }
      }
    },
    "analysis.getSignature": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "dartdoc": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          },
          "name": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          },
          "parameters": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "ParameterInfo"
              }
            }
          }
        }
      }
    },
    "analysis.reanalyze": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": null,
      "result": null
    },
    "analysis.setAnalysisRoots": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "excluded": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "FilePath"
              }
            }
          },
          "included": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "FilePath"
              }
            }
          },
          "packageRoots": {
            "required": false,
            "shape": {
              "kind": "map",
              "key": {
                "kind": "ref",
                "name": "FilePath"
              },
              "value": {
                "kind": "ref",
                "name": "FilePath"
              }
            }
          }
        }
      },
      "result": null
    },
    "analysis.setGeneralSubscriptions": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "subscriptions": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "GeneralAnalysisService"
              }
            }
          }
        }
      },
      "result": null
    },
    "analysis.setPriorityFiles": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "files": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "FilePath"
              }
            }
          }
        }
      },
      "result": null
    },
    "analysis.setSubscriptions": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "subscriptions": {
            "required": true,
            "shape": {
              "kind": "map",
              "key": {
                "kind": "ref",
                "name": "AnalysisService"
              },
              "value": {
                "kind": "list",
                "item": {
                  "kind": "ref",
                  "name": "FilePath"
                }
              }
            }
          }
        }
      },
      "result": null
    },
    "analysis.updateContent": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "files": {
            "required": true,
            "shape": {
              "kind": "map",
              "key": {
                "kind": "ref",
                "name": "FilePath"
              },
              "value": {
                "kind": "union",
                "discriminator": "type",
                "options": [
                  {
                    "kind": "ref",
                    "name": "AddContentOverlay"
                  },
                  {
                    "kind": "ref",
                    "name": "ChangeContentOverlay"
                  },
                  {
                    "kind": "ref",
                    "name": "RemoveContentOverlay"
                  }
                ]
              }
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {}
      }
    },
    "analysis.updateOptions": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "options": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "AnalysisOptions"
            }
          }
        }
      },
      "result": null
    },
    "analytics.enable": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "value": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "bool"
            }
          }
        }
      },
      "result": null
    },
    "analytics.isEnabled": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": null,
      "result": {
        "kind": "object",
        "fields": {
          "enabled": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "bool"
            }
          }
        }
      }
    },
    "analytics.sendEvent": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "action": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          }
        }
      },
      "result": null
    },
    "analytics.sendTiming": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "event": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          },
          "millis": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      },
      "result": null
    },
    "completion.getSuggestionDetails2": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "completion": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          },
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "libraryUri": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "change": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "SourceChange"
            }
          },
          "completion": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          }
        }
      }
    },
    "completion.getSuggestions2": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "completionCaseMatchingMode": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "CompletionCaseMatchingMode"
            }
          },
          "completionMode": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "CompletionMode"
            }
          },
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "invocationCount": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "maxResults": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "timeout": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "isIncomplete": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "bool"
            }
          },
          "replacementLength": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "replacementOffset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "suggestions": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "CompletionSuggestion"
              }
            }
          }
        }
      }
    },
    "completion.registerLibraryPaths": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "paths": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "LibraryPathSet"
              }
            }
          }
        }
      },
      "result": null
    },
    "diagnostic.getDiagnostics": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": null,
      "result": {
        "kind": "object",
        "fields": {
          "contexts": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "ContextData"
              }
            }
          }
        }
      }
    },
    "diagnostic.getServerPort": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": null,
      "result": {
        "kind": "object",
        "fields": {
          "port": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      }
    },
    "edit.bulkFixes": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "codes": {
            "required": false,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "String"
              }
            }
          },
          "inTestMode": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "bool"
            }
          },
          "included": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "FilePath"
              }
            }
          },
          "updatePubspec": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "bool"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "details": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "BulkFix"
              }
            }
          },
          "edits": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "SourceFileEdit"
              }
            }
          },
          "message": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          }
        }
      }
    },
    "edit.format": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "lineLength": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "selectionLength": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "selectionOffset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "selectionOnly": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "bool"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "edits": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "SourceEdit"
              }
            }
          },
          "selectionLength": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "selectionOffset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      }
    },
    "edit.formatIfEnabled": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "directories": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "FilePath"
              }
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "edits": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "SourceFileEdit"
              }
            }
          }
        }
      }
    },
    "edit.getAssists": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "length": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "assists": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "SourceChange"
              }
            }
          }
        }
      }
    },
    "edit.getAvailableRefactorings": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "length": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "kinds": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "RefactoringKind"
              }
            }
          }
        }
      }
    },
    "edit.getFixes": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "fixes": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "AnalysisErrorFixes"
              }
            }
          }
        }
      }
    },
    "edit.getPostfixCompletion": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "key": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "change": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "SourceChange"
            }
          }
        }
      }
    },
    "edit.getRefactoring": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "kind": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "RefactoringKind"
            }
          },
          "length": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "options": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "RefactoringOptions"
            }
          },
          "validateOnly": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "bool"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "change": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "SourceChange"
            }
          },
          "feedback": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "RefactoringFeedback"
            }
          },
          "finalProblems": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "RefactoringProblem"
              }
            }
          },
          "initialProblems": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "RefactoringProblem"
              }
            }
          },
          "optionsProblems": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "RefactoringProblem"
              }
            }
          },
          "potentialEdits": {
            "required": false,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "String"
              }
            }
          }
        }
      }
    },
    "edit.getStatementCompletion": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "change": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "SourceChange"
            }
          },
          "whitespaceOnly": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "bool"
            }
          }
        }
      }
    },
    "edit.importElements": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "elements": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "ImportedElements"
              }
            }
          },
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "offset": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "edit": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "SourceFileEdit"
            }
          }
        }
      }
    },
    "edit.isPostfixCompletionApplicable": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "key": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "value": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "bool"
            }
          }
        }
      }
    },
    "edit.listPostfixCompletionTemplates": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": null,
      "result": {
        "kind": "object",
        "fields": {
          "templates": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "PostfixTemplateDescriptor"
              }
            }
          }
        }
      }
    },
    "edit.organizeDirectives": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "edit": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "SourceFileEdit"
            }
          }
        }
      }
    },
    "edit.sortMembers": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "edit": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "SourceFileEdit"
            }
          }
        }
      }
    },
    "execution.createContext": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "contextRoot": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "id": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "ExecutionContextId"
            }
          }
        }
      }
    },
    "execution.deleteContext": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "id": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "ExecutionContextId"
            }
          }
        }
      },
      "result": null
    },
    "execution.getSuggestions": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "code": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          },
          "contextFile": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "contextOffset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "expressions": {
            "required": false,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "RuntimeCompletionExpression"
              }
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "variables": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "RuntimeCompletionVariable"
              }
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "expressions": {
            "required": false,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "RuntimeCompletionExpression"
              }
            }
          },
          "suggestions": {
            "required": false,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "CompletionSuggestion"
              }
            }
          }
        }
      }
    },
    "execution.mapUri": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "id": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "ExecutionContextId"
            }
          },
          "uri": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "file": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "uri": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          }
        }
      }
    },
    "execution.setSubscriptions": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "subscriptions": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "ExecutionService"
              }
            }
          }
        }
      },
      "result": null
    },
    "flutter.getWidgetDescription": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "properties": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "FlutterWidgetProperty"
              }
            }
          }
        }
      }
    },
    "flutter.setSubscriptions": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "subscriptions": {
            "required": true,
            "shape": {
              "kind": "map",
              "key": {
                "kind": "ref",
                "name": "FlutterService"
              },
              "value": {
                "kind": "list",
                "item": {
                  "kind": "ref",
                  "name": "FilePath"
                }
              }
            }
          }
        }
      },
      "result": null
    },
    "flutter.setWidgetPropertyValue": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "id": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "value": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "FlutterWidgetPropertyValue"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "change": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "SourceChange"
            }
          }
        }
      }
    },
    "lsp.handle": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "lspMessage": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "object"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "lspResponse": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "object"
            }
          }
        }
      }
    },
    "search.findElementReferences": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "includePotential": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "bool"
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "element": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "Element"
            }
          },
          "id": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "SearchId"
            }
          }
        }
      }
    },
    "search.findMemberDeclarations": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "name": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "id": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "SearchId"
            }
          }
        }
      }
    },
    "search.findMemberReferences": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "name": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "id": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "SearchId"
            }
          }
        }
      }
    },
    "search.findTopLevelDeclarations": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "pattern": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "id": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "SearchId"
            }
          }
        }
      }
    },
    "search.getElementDeclarations": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "maxResults": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "pattern": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "declarations": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "ElementDeclaration"
              }
            }
          },
          "files": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "FilePath"
              }
            }
          }
        }
      }
    },
    "search.getTypeHierarchy": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "superOnly": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "bool"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "hierarchyItems": {
            "required": false,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "TypeHierarchyItem"
              }
            }
          }
        }
      }
    },
    "server.cancelRequest": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "id": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          }
        }
      },
      "result": null
    },
    "server.getVersion": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": null,
      "result": {
        "kind": "object",
        "fields": {
          "version": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          }
        }
      }
    },
    "server.openUrlRequest": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "url": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          }
        }
      },
      "result": null
    },
    "server.setClientCapabilities": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "lspCapabilities": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "object"
            }
          },
          "requests": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "String"
              }
            }
          },
          "supportsUris": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "bool"
            }
          }
        }
      },
      "result": null
    },
    "server.setSubscriptions": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "subscriptions": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "ServerService"
              }
            }
          }
        }
      },
      "result": null
    },
    "server.showMessageRequest": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "actions": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "MessageAction"
              }
            }
          },
          "message": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          },
          "type": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "MessageType"
            }
          }
        }
      },
      "result": {
        "kind": "object",
        "fields": {
          "action": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          }
        }
      }
    },
    "server.shutdown": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": null,
      "result": null
    }
  },
  "notifications": {
    "analysis.analyzedFiles": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "directories": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "FilePath"
              }
            }
          }
        }
      }
    },
    "analysis.closingLabels": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "labels": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "ClosingLabel"
              }
            }
          }
        }
      }
    },
    "analysis.errors": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "errors": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "AnalysisError"
              }
            }
          },
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          }
        }
      }
    },
    "analysis.flushResults": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "files": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "FilePath"
              }
            }
          }
        }
      }
    },
    "analysis.folding": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "regions": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "FoldingRegion"
              }
            }
          }
        }
      }
    },
    "analysis.highlights": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "regions": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "HighlightRegion"
              }
            }
          }
        }
      }
    },
    "analysis.implemented": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "classes": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "ImplementedClass"
              }
            }
          },
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "members": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "ImplementedMember"
              }
            }
          }
        }
      }
    },
    "analysis.invalidate": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "delta": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "length": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "offset": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      }
    },
    "analysis.navigation": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "files": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "FilePath"
              }
            }
          },
          "regions": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "NavigationRegion"
              }
            }
          },
          "targets": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "NavigationTarget"
              }
            }
          }
        }
      }
    },
    "analysis.occurrences": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "occurrences": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "Occurrences"
              }
            }
          }
        }
      }
    },
    "analysis.outline": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "kind": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FileKind"
            }
          },
          "libraryName": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          },
          "outline": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "Outline"
            }
          }
        }
      }
    },
    "analysis.overrides": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "overrides": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "Override"
              }
            }
          }
        }
      }
    },
    "completion.existingImports": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "imports": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "ExistingImports"
            }
          }
        }
      }
    },
    "execution.launchData": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "kind": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "ExecutableKind"
            }
          },
          "referencedFiles": {
            "required": false,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "FilePath"
              }
            }
          }
        }
      }
    },
    "flutter.outline": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "file": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FilePath"
            }
          },
          "outline": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "FlutterOutline"
            }
          }
        }
      }
    },
    "lsp.notification": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "lspNotification": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "object"
            }
          }
        }
      }
    },
    "search.results": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "id": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "SearchId"
            }
          },
          "isLast": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "bool"
            }
          },
          "results": {
            "required": true,
            "shape": {
              "kind": "list",
              "item": {
                "kind": "ref",
                "name": "SearchResult"
              }
            }
          }
        }
      }
    },
    "server.connected": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "pid": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "int"
            }
          },
          "version": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          }
        }
      }
    },
    "server.error": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "isFatal": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "bool"
            }
          },
          "message": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          },
          "stackTrace": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          }
        }
      }
    },
    "server.log": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "entry": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "ServerLogEntry"
            }
          }
        }
      }
    },
    "server.pluginError": {
      "introduced": "1.40.1",
      "minimum": false,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "message": {
            "required": true,
            "shape": {
              "kind": "ref",
              "name": "String"
            }
          }
        }
      }
    },
    "server.status": {
      "introduced": "1.38.0",
      "minimum": true,
      "current": true,
      "params": {
        "kind": "object",
        "fields": {
          "analysis": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "AnalysisStatus"
            }
          },
          "pub": {
            "required": false,
            "shape": {
              "kind": "ref",
              "name": "PubStatus"
            }
          }
        }
      }
    }
  },
  "types": {
    "AnalysisErrorFixes": {
      "kind": "object",
      "fields": {
        "error": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "AnalysisError"
          }
        },
        "fixes": {
          "required": true,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "SourceChange"
            }
          }
        }
      }
    },
    "AnalysisOptions": {
      "kind": "object",
      "fields": {
        "enableAsync": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "bool"
          }
        },
        "enableDeferredLoading": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "bool"
          }
        },
        "enableEnums": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "bool"
          }
        },
        "enableNullAwareOperators": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "bool"
          }
        },
        "generateDart2jsHints": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "bool"
          }
        },
        "generateHints": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "bool"
          }
        },
        "generateLints": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "bool"
          }
        }
      }
    },
    "AnalysisService": {
      "kind": "enum",
      "values": [
        "CLOSING_LABELS",
        "FOLDING",
        "HIGHLIGHTS",
        "IMPLEMENTED",
        "INVALIDATE",
        "NAVIGATION",
        "OCCURRENCES",
        "OUTLINE",
        "OVERRIDES"
      ]
    },
    "AnalysisStatus": {
      "kind": "object",
      "fields": {
        "analysisTarget": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "isAnalyzing": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "bool"
          }
        }
      }
    },
    "BulkFix": {
      "kind": "object",
      "fields": {
        "fixes": {
          "required": true,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "BulkFixDetail"
            }
          }
        },
        "path": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "FilePath"
          }
        }
      }
    },
    "BulkFixDetail": {
      "kind": "object",
      "fields": {
        "code": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "occurrences": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        }
      }
    },
    "ClosingLabel": {
      "kind": "object",
      "fields": {
        "label": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "length": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "offset": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        }
      }
    },
    "CompletionCaseMatchingMode": {
      "kind": "enum",
      "values": [
        "FIRST_CHAR",
        "ALL_CHARS",
        "NONE"
      ]
    },
    "CompletionMode": {
      "kind": "enum",
      "values": [
        "BASIC",
        "SMART"
      ]
    },
    "ContextData": {
      "kind": "object",
      "fields": {
        "cacheEntryExceptions": {
          "required": true,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "String"
            }
          }
        },
        "explicitFileCount": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "implicitFileCount": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "name": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "workItemQueueLength": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        }
      }
    },
    "ElementDeclaration": {
      "kind": "object",
      "fields": {
        "className": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "codeLength": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "codeOffset": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "column": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "fileIndex": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "kind": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "ElementKind"
          }
        },
        "line": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "mixinName": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "name": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "offset": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "parameters": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        }
      }
    },
    "ExecutableFile": {
      "kind": "object",
      "fields": {
        "file": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "FilePath"
          }
        },
        "kind": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "ExecutableKind"
          }
        }
      }
    },
    "ExecutableKind": {
      "kind": "enum",
      "values": [
        "CLIENT",
        "EITHER",
        "NOT_EXECUTABLE",
        "SERVER"
      ]
    },
    "ExecutionContextId": {
      "kind": "ref",
      "name": "String"
    },
    "ExecutionService": {
      "kind": "enum",
      "values": [
        "LAUNCH_DATA"
      ]
    },
    "ExistingImport": {
      "kind": "object",
      "fields": {
        "elements": {
          "required": true,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "int"
            }
          }
        },
        "uri": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        }
      }
    },
    "ExistingImports": {
      "kind": "object",
      "fields": {
        "elements": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "ImportedElementSet"
          }
        },
        "imports": {
          "required": true,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "ExistingImport"
            }
          }
        }
      }
    },
    "FileKind": {
      "kind": "enum",
      "values": [
        "LIBRARY",
        "PART"
      ]
    },
    "FlutterOutline": {
      "kind": "object",
      "fields": {
        "attributes": {
          "required": false,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "FlutterOutlineAttribute"
            }
          }
        },
        "children": {
          "required": false,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "FlutterOutline"
            }
          }
        },
        "className": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "codeLength": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "codeOffset": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "dartElement": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "Element"
          }
        },
        "kind": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "FlutterOutlineKind"
          }
        },
        "label": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "length": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "offset": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "parentAssociationLabel": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "variableName": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        }
      }
    },
    "FlutterOutlineAttribute": {
      "kind": "object",
      "fields": {
        "label": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "literalValueBoolean": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "bool"
          }
        },
        "literalValueInteger": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "literalValueString": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "name": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "nameLocation": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "Location"
          }
        },
        "valueLocation": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "Location"
          }
        }
      }
    },
    "FlutterOutlineKind": {
      "kind": "enum",
      "values": [
        "DART_ELEMENT",
        "GENERIC",
        "NEW_INSTANCE",
        "INVOCATION",
        "VARIABLE",
        "PLACEHOLDER"
      ]
    },
    "FlutterService": {
      "kind": "enum",
      "values": [
        "OUTLINE"
      ]
    },
    "FlutterWidgetProperty": {
      "kind": "object",
      "fields": {
        "children": {
          "required": false,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "FlutterWidgetProperty"
            }
          }
        },
        "documentation": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "editor": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "FlutterWidgetPropertyEditor"
          }
        },
        "expression": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "id": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "isRequired": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "bool"
          }
        },
        "isSafeToUpdate": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "bool"
          }
        },
        "name": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "value": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "FlutterWidgetPropertyValue"
          }
        }
      }
    },
    "FlutterWidgetPropertyEditor": {
      "kind": "object",
      "fields": {
        "enumItems": {
          "required": false,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "FlutterWidgetPropertyValueEnumItem"
            }
          }
        },
        "kind": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "FlutterWidgetPropertyEditorKind"
          }
        }
      }
    },
    "FlutterWidgetPropertyEditorKind": {
      "kind": "enum",
      "values": [
        "BOOL",
        "DOUBLE",
        "ENUM",
        "ENUM_LIKE",
        "INT",
        "STRING"
      ]
    },
    "FlutterWidgetPropertyValue": {
      "kind": "object",
      "fields": {
        "boolValue": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "bool"
          }
        },
        "doubleValue": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "double"
          }
        },
        "enumValue": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "FlutterWidgetPropertyValueEnumItem"
          }
        },
        "expression": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "intValue": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "stringValue": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        }
      }
    },
    "FlutterWidgetPropertyValueEnumItem": {
      "kind": "object",
      "fields": {
        "className": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "documentation": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "libraryUri": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "name": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        }
      }
    },
    "GeneralAnalysisService": {
      "kind": "enum",
      "values": [
        "ANALYZED_FILES"
      ]
    },
    "HoverInformation": {
      "kind": "object",
      "fields": {
        "containingClassDescription": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "containingLibraryName": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "containingLibraryPath": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "dartdoc": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "elementDescription": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "elementKind": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "isDeprecated": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "bool"
          }
        },
        "length": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "offset": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "parameter": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "propagatedType": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "staticType": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        }
      }
    },
    "ImplementedClass": {
      "kind": "object",
      "fields": {
        "length": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "offset": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        }
      }
    },
    "ImplementedMember": {
      "kind": "object",
      "fields": {
        "length": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "offset": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        }
      }
    },
    "ImportedElementSet": {
      "kind": "object",
      "fields": {
        "names": {
          "required": true,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "int"
            }
          }
        },
        "strings": {
          "required": true,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "String"
            }
          }
        },
        "uris": {
          "required": true,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "int"
            }
          }
        }
      }
    },
    "ImportedElements": {
      "kind": "object",
      "fields": {
        "elements": {
          "required": true,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "String"
            }
          }
        },
        "path": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "FilePath"
          }
        },
        "prefix": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        }
      }
    },
    "LibraryPathSet": {
      "kind": "object",
      "fields": {
        "libraryPaths": {
          "required": true,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "FilePath"
            }
          }
        },
        "scope": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "FilePath"
          }
        }
      }
    },
    "MessageAction": {
      "kind": "object",
      "fields": {
        "label": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        }
      }
    },
    "MessageType": {
      "kind": "enum",
      "values": [
        "ERROR",
        "WARNING",
        "INFO",
        "LOG"
      ]
    },
    "OverriddenMember": {
      "kind": "object",
      "fields": {
        "className": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "element": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "Element"
          }
        }
      }
    },
    "Override": {
      "kind": "object",
      "fields": {
        "interfaceMembers": {
          "required": false,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "OverriddenMember"
            }
          }
        },
        "length": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "offset": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "superclassMember": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "OverriddenMember"
          }
        }
      }
    },
    "PostfixTemplateDescriptor": {
      "kind": "object",
      "fields": {
        "example": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "key": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "name": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        }
      }
    },
    "PubStatus": {
      "kind": "object",
      "fields": {
        "isListingPackageDirs": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "bool"
          }
        }
      }
    },
    "RefactoringFeedback": {
      "kind": "object",
      "fields": {}
    },
    "RefactoringOptions": {
      "kind": "object",
      "fields": {}
    },
    "RequestError": {
      "kind": "object",
      "fields": {
        "code": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "RequestErrorCode"
          }
        },
        "message": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "stackTrace": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        }
      }
    },
    "RequestErrorCode": {
      "kind": "enum",
      "values": [
        "CONTENT_MODIFIED",
        "DEBUG_PORT_COULD_NOT_BE_OPENED",
        "FILE_NOT_ANALYZED",
        "FLUTTER_GET_WIDGET_DESCRIPTION_CONTENT_MODIFIED",
        "FLUTTER_GET_WIDGET_DESCRIPTION_NO_WIDGET",
        "FLUTTER_SET_WIDGET_PROPERTY_VALUE_INVALID_EXPRESSION",
        "FLUTTER_SET_WIDGET_PROPERTY_VALUE_INVALID_ID",
        "FLUTTER_SET_WIDGET_PROPERTY_VALUE_IS_REQUIRED",
        "FORMAT_INVALID_FILE",
        "FORMAT_WITH_ERRORS",
        "GET_ERRORS_INVALID_FILE",
        "GET_FIXES_INVALID_FILE",
        "GET_IMPORTED_ELEMENTS_INVALID_FILE",
        "GET_NAVIGATION_INVALID_FILE",
        "GET_REACHABLE_SOURCES_INVALID_FILE",
        "GET_SIGNATURE_INVALID_FILE",
        "GET_SIGNATURE_INVALID_OFFSET",
        "GET_SIGNATURE_UNKNOWN_FUNCTION",
        "IMPORT_ELEMENTS_INVALID_FILE",
        "INVALID_ANALYSIS_ROOT",
        "INVALID_EXECUTION_CONTEXT",
        "INVALID_FILE_PATH_FORMAT",
        "INVALID_OVERLAY_CHANGE",
        "INVALID_PARAMETER",
        "INVALID_REQUEST",
        "ORGANIZE_DIRECTIVES_ERROR",
        "REFACTORING_REQUEST_CANCELLED",
        "SERVER_ALREADY_STARTED",
        "SERVER_ERROR",
        "SORT_MEMBERS_INVALID_FILE",
        "SORT_MEMBERS_PARSE_ERRORS",
        "UNKNOWN_REQUEST",
        "UNSUPPORTED_FEATURE"
      ]
    },
    "RuntimeCompletionExpression": {
      "kind": "object",
      "fields": {
        "length": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "offset": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        },
        "type": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "RuntimeCompletionExpressionType"
          }
        }
      }
    },
    "RuntimeCompletionExpressionType": {
      "kind": "object",
      "fields": {
        "kind": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "RuntimeCompletionExpressionTypeKind"
          }
        },
        "libraryPath": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "FilePath"
          }
        },
        "name": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "parameterNames": {
          "required": false,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "String"
            }
          }
        },
        "parameterTypes": {
          "required": false,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "RuntimeCompletionExpressionType"
            }
          }
        },
        "returnType": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "RuntimeCompletionExpressionType"
          }
        },
        "typeArguments": {
          "required": false,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "RuntimeCompletionExpressionType"
            }
          }
        }
      }
    },
    "RuntimeCompletionExpressionTypeKind": {
      "kind": "enum",
      "values": [
        "DYNAMIC",
        "FUNCTION",
        "INTERFACE"
      ]
    },
    "RuntimeCompletionVariable": {
      "kind": "object",
      "fields": {
        "name": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "type": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "RuntimeCompletionExpressionType"
          }
        }
      }
    },
    "SearchId": {
      "kind": "ref",
      "name": "String"
    },
    "SearchResult": {
      "kind": "object",
      "fields": {
        "isPotential": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "bool"
          }
        },
        "kind": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "SearchResultKind"
          }
        },
        "location": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "Location"
          }
        },
        "path": {
          "required": true,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "Element"
            }
          }
        }
      }
    },
    "SearchResultKind": {
      "kind": "enum",
      "values": [
        "DECLARATION",
        "INVOCATION",
        "READ",
        "READ_WRITE",
        "REFERENCE",
        "UNKNOWN",
        "WRITE"
      ]
    },
    "ServerLogEntry": {
      "kind": "object",
      "fields": {
        "data": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "kind": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "ServerLogEntryKind"
          }
        },
        "time": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        }
      }
    },
    "ServerLogEntryKind": {
      "kind": "enum",
      "values": [
        "NOTIFICATION",
        "RAW",
        "REQUEST",
        "RESPONSE"
      ]
    },
    "ServerService": {
      "kind": "enum",
      "values": [
        "LOG",
        "STATUS"
      ]
    },
    "TypeHierarchyItem": {
      "kind": "object",
      "fields": {
        "classElement": {
          "required": true,
          "shape": {
            "kind": "ref",
            "name": "Element"
          }
        },
        "displayName": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "String"
          }
        },
        "interfaces": {
          "required": true,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "int"
            }
          }
        },
        "memberElement": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "Element"
          }
        },
        "mixins": {
          "required": true,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "int"
            }
          }
        },
        "subclasses": {
          "required": true,
          "shape": {
            "kind": "list",
            "item": {
              "kind": "ref",
              "name": "int"
            }
          }
        },
        "superclass": {
          "required": false,
          "shape": {
            "kind": "ref",
            "name": "int"
          }
        }
      }
    }
  },
  "enums": {
    "AnalysisService": [
      "CLOSING_LABELS",
      "FOLDING",
      "HIGHLIGHTS",
      "IMPLEMENTED",
      "INVALIDATE",
      "NAVIGATION",
      "OCCURRENCES",
      "OUTLINE",
      "OVERRIDES"
    ],
    "CompletionCaseMatchingMode": [
      "ALL_CHARS",
      "FIRST_CHAR",
      "NONE"
    ],
    "CompletionMode": [
      "BASIC",
      "SMART"
    ],
    "ExecutableKind": [
      "CLIENT",
      "EITHER",
      "NOT_EXECUTABLE",
      "SERVER"
    ],
    "ExecutionService": [
      "LAUNCH_DATA"
    ],
    "FileKind": [
      "LIBRARY",
      "PART"
    ],
    "FlutterOutlineKind": [
      "DART_ELEMENT",
      "GENERIC",
      "INVOCATION",
      "NEW_INSTANCE",
      "PLACEHOLDER",
      "VARIABLE"
    ],
    "FlutterService": [
      "OUTLINE"
    ],
    "FlutterWidgetPropertyEditorKind": [
      "BOOL",
      "DOUBLE",
      "ENUM",
      "ENUM_LIKE",
      "INT",
      "STRING"
    ],
    "GeneralAnalysisService": [
      "ANALYZED_FILES"
    ],
    "MessageType": [
      "ERROR",
      "INFO",
      "LOG",
      "WARNING"
    ],
    "RequestErrorCode": [
      "CONTENT_MODIFIED",
      "DEBUG_PORT_COULD_NOT_BE_OPENED",
      "FILE_NOT_ANALYZED",
      "FLUTTER_GET_WIDGET_DESCRIPTION_CONTENT_MODIFIED",
      "FLUTTER_GET_WIDGET_DESCRIPTION_NO_WIDGET",
      "FLUTTER_SET_WIDGET_PROPERTY_VALUE_INVALID_EXPRESSION",
      "FLUTTER_SET_WIDGET_PROPERTY_VALUE_INVALID_ID",
      "FLUTTER_SET_WIDGET_PROPERTY_VALUE_IS_REQUIRED",
      "FORMAT_INVALID_FILE",
      "FORMAT_WITH_ERRORS",
      "GET_ERRORS_INVALID_FILE",
      "GET_FIXES_INVALID_FILE",
      "GET_IMPORTED_ELEMENTS_INVALID_FILE",
      "GET_NAVIGATION_INVALID_FILE",
      "GET_REACHABLE_SOURCES_INVALID_FILE",
      "GET_SIGNATURE_INVALID_FILE",
      "GET_SIGNATURE_INVALID_OFFSET",
      "GET_SIGNATURE_UNKNOWN_FUNCTION",
      "IMPORT_ELEMENTS_INVALID_FILE",
      "INVALID_ANALYSIS_ROOT",
      "INVALID_EXECUTION_CONTEXT",
      "INVALID_FILE_PATH_FORMAT",
      "INVALID_OVERLAY_CHANGE",
      "INVALID_PARAMETER",
      "INVALID_REQUEST",
      "ORGANIZE_DIRECTIVES_ERROR",
      "REFACTORING_REQUEST_CANCELLED",
      "SERVER_ALREADY_STARTED",
      "SERVER_ERROR",
      "SORT_MEMBERS_INVALID_FILE",
      "SORT_MEMBERS_PARSE_ERRORS",
      "UNKNOWN_REQUEST",
      "UNSUPPORTED_FEATURE"
    ],
    "RuntimeCompletionExpressionTypeKind": [
      "DYNAMIC",
      "FUNCTION",
      "INTERFACE"
    ],
    "SearchResultKind": [
      "DECLARATION",
      "INVOCATION",
      "READ",
      "READ_WRITE",
      "REFERENCE",
      "UNKNOWN",
      "WRITE"
    ],
    "ServerLogEntryKind": [
      "NOTIFICATION",
      "RAW",
      "REQUEST",
      "RESPONSE"
    ],
    "ServerService": [
      "LOG",
      "STATUS"
    ]
  },
  "changedDefinitions": [
    "request:server.setClientCapabilities"
  ],
  "unclassifiedChangedDefinitions": []
}''';
