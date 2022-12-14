import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/constant/value.dart' show DartObject;

import 'package:build/src/builder/build_step.dart';
import 'package:bloc_use_case_generator/src/error/invalid_argument.dart';
import 'package:bloc_use_case_generator/src/error/required_field_error.dart';
import 'package:bloc_use_case_generator/src/model/use_case.dart';
import 'package:source_gen/source_gen.dart';
import 'package:bloc_use_case_generator/src/model/use_case_state.dart' as helper;
import '../../bloc_generator.dart';

class BlocGenerator extends GeneratorForAnnotation<BlocAnnotation> {
  @override
  String generateForAnnotatedElement(Element element, ConstantReader annotation, BuildStep buildStep) {
    final blocName = element.name?.replaceFirst('Bloc', '');
    final baseEventType = annotation.read('baseEventType').typeValue.toString().replaceAll("*", "");
    final baseStateType = annotation.read('baseStateType').typeValue.toString().replaceAll("*", "");
    String? globalFailureModel;

    try {
      globalFailureModel = annotation.read('failureModel').typeValue.toString().replaceAll("*", "");
    } on FormatException {
      globalFailureModel = null;
    }

    if (blocName == null) {
      throw RequiredFieldError(fieldName: 'name');
    }

    var useCases = annotation.read('blocUseCases').listValue;
    final List<UseCase> useCaseModels = [];
    for (final useCase in useCases) {
      final outputDartMap = useCase.getField('output')?.toMapValue();
      final inputDartMap = useCase.getField('input')?.toMapValue();
      final name = useCase.getField('name')?.toStringValue();

      final failureModel = dartObjectToTypeString(useCase.getField('failureModel'));

      if (name == null) {
        throw RequiredFieldError(fieldName: 'name');
      }

      final extraStatesDartList = useCase.getField('extraStates')?.toListValue();

      Map<String, String> outputs = {};
      if (outputDartMap != null) {
        for (var entry in outputDartMap.entries) {
          var key = entry.key?.toStringValue();

          var type = dartObjectToTypeString(entry.value);

          if (key == null || type == null) {
            throw InvalidArgumentException(
              fieldName: 'output',
              correctUsage: "{'name':type}",
            );
          }
          outputs[key] = type;
        }
      }

      Map<String, String> inputs = {};
      if (inputDartMap != null) {
        for (var entry in inputDartMap.entries) {
          var key = entry.key?.toStringValue();
          var type = dartObjectToTypeString(entry.value);
          if (key == null || type == null) {
            throw InvalidArgumentException(
              fieldName: 'input',
              correctUsage: "{'name':type}",
            );
          }
          inputs[key] = type;
        }
      }

      List<helper.UseCaseState> extraStates = [];
      if (extraStatesDartList != null) {
        for (var extraState in extraStatesDartList) {
          String? name = extraState.getField('name')?.toStringValue();
          Map<DartObject?, DartObject?>? arguments = extraState.getField('arguments')?.toMapValue();

          if (name == null) {
            continue;
          }

          Map<String, String> argumentsAsStringMap = {};
          if (arguments != null) {
            for (var entry in arguments.entries) {
              var key = entry.key?.toStringValue();
              var type = dartObjectToTypeString(entry.value);

              if (key != null && type != null) {
                argumentsAsStringMap[key] = type;
              }
            }
          }

          final extraStateModel = helper.UseCaseState(
            name: name,
            arguments: argumentsAsStringMap,
          );
          extraStates.add(extraStateModel);
        }
      }

      useCaseModels.add(UseCase(
        name: name,
        inputs: inputs,
        outputs: outputs,
        extraStates: extraStates,
        failureModel: failureModel,
      ));
    }

    final buffer = StringBuffer();

    buffer.writeln("class Initial${blocName}State extends $baseStateType{}");
    for (final model in useCaseModels) {
      buffer.writeln('class ${model.name}Event extends $baseEventType{');
      if (model.inputs.isNotEmpty) {
        _writeIO(buffer, model.inputs, '${model.name}Event');
      }
      buffer.writeln('}');

      buffer.writeln('class ${model.name}InProgressState extends $baseStateType{}');

      if (model.extraStates.isNotEmpty) {
        for (var state in model.extraStates) {
          buffer.writeln("class ${state.name}State extends $baseStateType{");
          if (state.arguments != null) {
            _writeIO(buffer, state.arguments!, '${state.name}State');
          }

          buffer.writeln("}");
        }
      }

      buffer.writeln('class ${model.name}CompletedState extends $baseStateType{');
      if (model.outputs.isNotEmpty) {
        _writeIO(buffer, model.outputs, '${model.name}CompletedState');
      }
      buffer.writeln('}');
      buffer.writeln('class ${model.name}FailedState extends $baseStateType{');

      String? failureModel;
      if (model.failureModel != null && model.failureModel != "null") {
        failureModel = model.failureModel;
      } else {
        failureModel = globalFailureModel;
      }

      if (failureModel != "null" && failureModel != null) {
        buffer.writeln("final $failureModel failure;");
        buffer.writeln("${model.name}FailedState({required this.failure});");
      }

      buffer.writeln("}");
    }

    return buffer.toString();
  }

  String? dartObjectToTypeString(DartObject? dartObj) {
    String? type = dartObj?.toTypeValue().toString().replaceAll("*", "");

    if (type == null) return null;

    if (type.contains("Nullable")) {
      print('printing values');
      print(type);
      type = type.replaceFirst('Nullable<', '');
      type = type.replaceFirst('>', '');
      type = type + '?';
    }
    return type;
  }

  void _writeIO(StringBuffer buffer, Map<String, String> map, String constructorName) {
    for (var input in map.entries) {
      buffer.writeln('final ${input.value} ${input.key};');
    }
    buffer.writeln(constructorName);
    var fields = map.keys.map((e) => 'required this.$e').join(',');
    if (fields.isNotEmpty) {
      buffer.writeln('({$fields});');
    } else {
      buffer.writeln('();');
    }
  }
}
