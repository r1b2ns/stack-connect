// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$StackError {
  String get message => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String message) invalidCredentials,
    required TResult Function(String message) auth,
    required TResult Function(String message) pendingAgreements,
    required TResult Function(int status, String message) http,
    required TResult Function(String message) decode,
    required TResult Function(String message) network,
    required TResult Function(String message) unsupported,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String message)? invalidCredentials,
    TResult? Function(String message)? auth,
    TResult? Function(String message)? pendingAgreements,
    TResult? Function(int status, String message)? http,
    TResult? Function(String message)? decode,
    TResult? Function(String message)? network,
    TResult? Function(String message)? unsupported,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String message)? invalidCredentials,
    TResult Function(String message)? auth,
    TResult Function(String message)? pendingAgreements,
    TResult Function(int status, String message)? http,
    TResult Function(String message)? decode,
    TResult Function(String message)? network,
    TResult Function(String message)? unsupported,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(StackError_InvalidCredentials value)
    invalidCredentials,
    required TResult Function(StackError_Auth value) auth,
    required TResult Function(StackError_PendingAgreements value)
    pendingAgreements,
    required TResult Function(StackError_Http value) http,
    required TResult Function(StackError_Decode value) decode,
    required TResult Function(StackError_Network value) network,
    required TResult Function(StackError_Unsupported value) unsupported,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(StackError_InvalidCredentials value)? invalidCredentials,
    TResult? Function(StackError_Auth value)? auth,
    TResult? Function(StackError_PendingAgreements value)? pendingAgreements,
    TResult? Function(StackError_Http value)? http,
    TResult? Function(StackError_Decode value)? decode,
    TResult? Function(StackError_Network value)? network,
    TResult? Function(StackError_Unsupported value)? unsupported,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(StackError_InvalidCredentials value)? invalidCredentials,
    TResult Function(StackError_Auth value)? auth,
    TResult Function(StackError_PendingAgreements value)? pendingAgreements,
    TResult Function(StackError_Http value)? http,
    TResult Function(StackError_Decode value)? decode,
    TResult Function(StackError_Network value)? network,
    TResult Function(StackError_Unsupported value)? unsupported,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $StackErrorCopyWith<StackError> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $StackErrorCopyWith<$Res> {
  factory $StackErrorCopyWith(
    StackError value,
    $Res Function(StackError) then,
  ) = _$StackErrorCopyWithImpl<$Res, StackError>;
  @useResult
  $Res call({String message});
}

/// @nodoc
class _$StackErrorCopyWithImpl<$Res, $Val extends StackError>
    implements $StackErrorCopyWith<$Res> {
  _$StackErrorCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = null}) {
    return _then(
      _value.copyWith(
            message: null == message
                ? _value.message
                : message // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$StackError_InvalidCredentialsImplCopyWith<$Res>
    implements $StackErrorCopyWith<$Res> {
  factory _$$StackError_InvalidCredentialsImplCopyWith(
    _$StackError_InvalidCredentialsImpl value,
    $Res Function(_$StackError_InvalidCredentialsImpl) then,
  ) = __$$StackError_InvalidCredentialsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$StackError_InvalidCredentialsImplCopyWithImpl<$Res>
    extends _$StackErrorCopyWithImpl<$Res, _$StackError_InvalidCredentialsImpl>
    implements _$$StackError_InvalidCredentialsImplCopyWith<$Res> {
  __$$StackError_InvalidCredentialsImplCopyWithImpl(
    _$StackError_InvalidCredentialsImpl _value,
    $Res Function(_$StackError_InvalidCredentialsImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = null}) {
    return _then(
      _$StackError_InvalidCredentialsImpl(
        message: null == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$StackError_InvalidCredentialsImpl
    extends StackError_InvalidCredentials {
  const _$StackError_InvalidCredentialsImpl({required this.message})
    : super._();

  @override
  final String message;

  @override
  String toString() {
    return 'StackError.invalidCredentials(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StackError_InvalidCredentialsImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$StackError_InvalidCredentialsImplCopyWith<
    _$StackError_InvalidCredentialsImpl
  >
  get copyWith =>
      __$$StackError_InvalidCredentialsImplCopyWithImpl<
        _$StackError_InvalidCredentialsImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String message) invalidCredentials,
    required TResult Function(String message) auth,
    required TResult Function(String message) pendingAgreements,
    required TResult Function(int status, String message) http,
    required TResult Function(String message) decode,
    required TResult Function(String message) network,
    required TResult Function(String message) unsupported,
  }) {
    return invalidCredentials(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String message)? invalidCredentials,
    TResult? Function(String message)? auth,
    TResult? Function(String message)? pendingAgreements,
    TResult? Function(int status, String message)? http,
    TResult? Function(String message)? decode,
    TResult? Function(String message)? network,
    TResult? Function(String message)? unsupported,
  }) {
    return invalidCredentials?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String message)? invalidCredentials,
    TResult Function(String message)? auth,
    TResult Function(String message)? pendingAgreements,
    TResult Function(int status, String message)? http,
    TResult Function(String message)? decode,
    TResult Function(String message)? network,
    TResult Function(String message)? unsupported,
    required TResult orElse(),
  }) {
    if (invalidCredentials != null) {
      return invalidCredentials(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(StackError_InvalidCredentials value)
    invalidCredentials,
    required TResult Function(StackError_Auth value) auth,
    required TResult Function(StackError_PendingAgreements value)
    pendingAgreements,
    required TResult Function(StackError_Http value) http,
    required TResult Function(StackError_Decode value) decode,
    required TResult Function(StackError_Network value) network,
    required TResult Function(StackError_Unsupported value) unsupported,
  }) {
    return invalidCredentials(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(StackError_InvalidCredentials value)? invalidCredentials,
    TResult? Function(StackError_Auth value)? auth,
    TResult? Function(StackError_PendingAgreements value)? pendingAgreements,
    TResult? Function(StackError_Http value)? http,
    TResult? Function(StackError_Decode value)? decode,
    TResult? Function(StackError_Network value)? network,
    TResult? Function(StackError_Unsupported value)? unsupported,
  }) {
    return invalidCredentials?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(StackError_InvalidCredentials value)? invalidCredentials,
    TResult Function(StackError_Auth value)? auth,
    TResult Function(StackError_PendingAgreements value)? pendingAgreements,
    TResult Function(StackError_Http value)? http,
    TResult Function(StackError_Decode value)? decode,
    TResult Function(StackError_Network value)? network,
    TResult Function(StackError_Unsupported value)? unsupported,
    required TResult orElse(),
  }) {
    if (invalidCredentials != null) {
      return invalidCredentials(this);
    }
    return orElse();
  }
}

abstract class StackError_InvalidCredentials extends StackError {
  const factory StackError_InvalidCredentials({required final String message}) =
      _$StackError_InvalidCredentialsImpl;
  const StackError_InvalidCredentials._() : super._();

  @override
  String get message;

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$StackError_InvalidCredentialsImplCopyWith<
    _$StackError_InvalidCredentialsImpl
  >
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$StackError_AuthImplCopyWith<$Res>
    implements $StackErrorCopyWith<$Res> {
  factory _$$StackError_AuthImplCopyWith(
    _$StackError_AuthImpl value,
    $Res Function(_$StackError_AuthImpl) then,
  ) = __$$StackError_AuthImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$StackError_AuthImplCopyWithImpl<$Res>
    extends _$StackErrorCopyWithImpl<$Res, _$StackError_AuthImpl>
    implements _$$StackError_AuthImplCopyWith<$Res> {
  __$$StackError_AuthImplCopyWithImpl(
    _$StackError_AuthImpl _value,
    $Res Function(_$StackError_AuthImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = null}) {
    return _then(
      _$StackError_AuthImpl(
        message: null == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$StackError_AuthImpl extends StackError_Auth {
  const _$StackError_AuthImpl({required this.message}) : super._();

  @override
  final String message;

  @override
  String toString() {
    return 'StackError.auth(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StackError_AuthImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$StackError_AuthImplCopyWith<_$StackError_AuthImpl> get copyWith =>
      __$$StackError_AuthImplCopyWithImpl<_$StackError_AuthImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String message) invalidCredentials,
    required TResult Function(String message) auth,
    required TResult Function(String message) pendingAgreements,
    required TResult Function(int status, String message) http,
    required TResult Function(String message) decode,
    required TResult Function(String message) network,
    required TResult Function(String message) unsupported,
  }) {
    return auth(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String message)? invalidCredentials,
    TResult? Function(String message)? auth,
    TResult? Function(String message)? pendingAgreements,
    TResult? Function(int status, String message)? http,
    TResult? Function(String message)? decode,
    TResult? Function(String message)? network,
    TResult? Function(String message)? unsupported,
  }) {
    return auth?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String message)? invalidCredentials,
    TResult Function(String message)? auth,
    TResult Function(String message)? pendingAgreements,
    TResult Function(int status, String message)? http,
    TResult Function(String message)? decode,
    TResult Function(String message)? network,
    TResult Function(String message)? unsupported,
    required TResult orElse(),
  }) {
    if (auth != null) {
      return auth(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(StackError_InvalidCredentials value)
    invalidCredentials,
    required TResult Function(StackError_Auth value) auth,
    required TResult Function(StackError_PendingAgreements value)
    pendingAgreements,
    required TResult Function(StackError_Http value) http,
    required TResult Function(StackError_Decode value) decode,
    required TResult Function(StackError_Network value) network,
    required TResult Function(StackError_Unsupported value) unsupported,
  }) {
    return auth(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(StackError_InvalidCredentials value)? invalidCredentials,
    TResult? Function(StackError_Auth value)? auth,
    TResult? Function(StackError_PendingAgreements value)? pendingAgreements,
    TResult? Function(StackError_Http value)? http,
    TResult? Function(StackError_Decode value)? decode,
    TResult? Function(StackError_Network value)? network,
    TResult? Function(StackError_Unsupported value)? unsupported,
  }) {
    return auth?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(StackError_InvalidCredentials value)? invalidCredentials,
    TResult Function(StackError_Auth value)? auth,
    TResult Function(StackError_PendingAgreements value)? pendingAgreements,
    TResult Function(StackError_Http value)? http,
    TResult Function(StackError_Decode value)? decode,
    TResult Function(StackError_Network value)? network,
    TResult Function(StackError_Unsupported value)? unsupported,
    required TResult orElse(),
  }) {
    if (auth != null) {
      return auth(this);
    }
    return orElse();
  }
}

abstract class StackError_Auth extends StackError {
  const factory StackError_Auth({required final String message}) =
      _$StackError_AuthImpl;
  const StackError_Auth._() : super._();

  @override
  String get message;

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$StackError_AuthImplCopyWith<_$StackError_AuthImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$StackError_PendingAgreementsImplCopyWith<$Res>
    implements $StackErrorCopyWith<$Res> {
  factory _$$StackError_PendingAgreementsImplCopyWith(
    _$StackError_PendingAgreementsImpl value,
    $Res Function(_$StackError_PendingAgreementsImpl) then,
  ) = __$$StackError_PendingAgreementsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$StackError_PendingAgreementsImplCopyWithImpl<$Res>
    extends _$StackErrorCopyWithImpl<$Res, _$StackError_PendingAgreementsImpl>
    implements _$$StackError_PendingAgreementsImplCopyWith<$Res> {
  __$$StackError_PendingAgreementsImplCopyWithImpl(
    _$StackError_PendingAgreementsImpl _value,
    $Res Function(_$StackError_PendingAgreementsImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = null}) {
    return _then(
      _$StackError_PendingAgreementsImpl(
        message: null == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$StackError_PendingAgreementsImpl extends StackError_PendingAgreements {
  const _$StackError_PendingAgreementsImpl({required this.message}) : super._();

  @override
  final String message;

  @override
  String toString() {
    return 'StackError.pendingAgreements(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StackError_PendingAgreementsImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$StackError_PendingAgreementsImplCopyWith<
    _$StackError_PendingAgreementsImpl
  >
  get copyWith =>
      __$$StackError_PendingAgreementsImplCopyWithImpl<
        _$StackError_PendingAgreementsImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String message) invalidCredentials,
    required TResult Function(String message) auth,
    required TResult Function(String message) pendingAgreements,
    required TResult Function(int status, String message) http,
    required TResult Function(String message) decode,
    required TResult Function(String message) network,
    required TResult Function(String message) unsupported,
  }) {
    return pendingAgreements(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String message)? invalidCredentials,
    TResult? Function(String message)? auth,
    TResult? Function(String message)? pendingAgreements,
    TResult? Function(int status, String message)? http,
    TResult? Function(String message)? decode,
    TResult? Function(String message)? network,
    TResult? Function(String message)? unsupported,
  }) {
    return pendingAgreements?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String message)? invalidCredentials,
    TResult Function(String message)? auth,
    TResult Function(String message)? pendingAgreements,
    TResult Function(int status, String message)? http,
    TResult Function(String message)? decode,
    TResult Function(String message)? network,
    TResult Function(String message)? unsupported,
    required TResult orElse(),
  }) {
    if (pendingAgreements != null) {
      return pendingAgreements(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(StackError_InvalidCredentials value)
    invalidCredentials,
    required TResult Function(StackError_Auth value) auth,
    required TResult Function(StackError_PendingAgreements value)
    pendingAgreements,
    required TResult Function(StackError_Http value) http,
    required TResult Function(StackError_Decode value) decode,
    required TResult Function(StackError_Network value) network,
    required TResult Function(StackError_Unsupported value) unsupported,
  }) {
    return pendingAgreements(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(StackError_InvalidCredentials value)? invalidCredentials,
    TResult? Function(StackError_Auth value)? auth,
    TResult? Function(StackError_PendingAgreements value)? pendingAgreements,
    TResult? Function(StackError_Http value)? http,
    TResult? Function(StackError_Decode value)? decode,
    TResult? Function(StackError_Network value)? network,
    TResult? Function(StackError_Unsupported value)? unsupported,
  }) {
    return pendingAgreements?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(StackError_InvalidCredentials value)? invalidCredentials,
    TResult Function(StackError_Auth value)? auth,
    TResult Function(StackError_PendingAgreements value)? pendingAgreements,
    TResult Function(StackError_Http value)? http,
    TResult Function(StackError_Decode value)? decode,
    TResult Function(StackError_Network value)? network,
    TResult Function(StackError_Unsupported value)? unsupported,
    required TResult orElse(),
  }) {
    if (pendingAgreements != null) {
      return pendingAgreements(this);
    }
    return orElse();
  }
}

abstract class StackError_PendingAgreements extends StackError {
  const factory StackError_PendingAgreements({required final String message}) =
      _$StackError_PendingAgreementsImpl;
  const StackError_PendingAgreements._() : super._();

  @override
  String get message;

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$StackError_PendingAgreementsImplCopyWith<
    _$StackError_PendingAgreementsImpl
  >
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$StackError_HttpImplCopyWith<$Res>
    implements $StackErrorCopyWith<$Res> {
  factory _$$StackError_HttpImplCopyWith(
    _$StackError_HttpImpl value,
    $Res Function(_$StackError_HttpImpl) then,
  ) = __$$StackError_HttpImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int status, String message});
}

/// @nodoc
class __$$StackError_HttpImplCopyWithImpl<$Res>
    extends _$StackErrorCopyWithImpl<$Res, _$StackError_HttpImpl>
    implements _$$StackError_HttpImplCopyWith<$Res> {
  __$$StackError_HttpImplCopyWithImpl(
    _$StackError_HttpImpl _value,
    $Res Function(_$StackError_HttpImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? status = null, Object? message = null}) {
    return _then(
      _$StackError_HttpImpl(
        status: null == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as int,
        message: null == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$StackError_HttpImpl extends StackError_Http {
  const _$StackError_HttpImpl({required this.status, required this.message})
    : super._();

  @override
  final int status;
  @override
  final String message;

  @override
  String toString() {
    return 'StackError.http(status: $status, message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StackError_HttpImpl &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, status, message);

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$StackError_HttpImplCopyWith<_$StackError_HttpImpl> get copyWith =>
      __$$StackError_HttpImplCopyWithImpl<_$StackError_HttpImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String message) invalidCredentials,
    required TResult Function(String message) auth,
    required TResult Function(String message) pendingAgreements,
    required TResult Function(int status, String message) http,
    required TResult Function(String message) decode,
    required TResult Function(String message) network,
    required TResult Function(String message) unsupported,
  }) {
    return http(status, message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String message)? invalidCredentials,
    TResult? Function(String message)? auth,
    TResult? Function(String message)? pendingAgreements,
    TResult? Function(int status, String message)? http,
    TResult? Function(String message)? decode,
    TResult? Function(String message)? network,
    TResult? Function(String message)? unsupported,
  }) {
    return http?.call(status, message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String message)? invalidCredentials,
    TResult Function(String message)? auth,
    TResult Function(String message)? pendingAgreements,
    TResult Function(int status, String message)? http,
    TResult Function(String message)? decode,
    TResult Function(String message)? network,
    TResult Function(String message)? unsupported,
    required TResult orElse(),
  }) {
    if (http != null) {
      return http(status, message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(StackError_InvalidCredentials value)
    invalidCredentials,
    required TResult Function(StackError_Auth value) auth,
    required TResult Function(StackError_PendingAgreements value)
    pendingAgreements,
    required TResult Function(StackError_Http value) http,
    required TResult Function(StackError_Decode value) decode,
    required TResult Function(StackError_Network value) network,
    required TResult Function(StackError_Unsupported value) unsupported,
  }) {
    return http(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(StackError_InvalidCredentials value)? invalidCredentials,
    TResult? Function(StackError_Auth value)? auth,
    TResult? Function(StackError_PendingAgreements value)? pendingAgreements,
    TResult? Function(StackError_Http value)? http,
    TResult? Function(StackError_Decode value)? decode,
    TResult? Function(StackError_Network value)? network,
    TResult? Function(StackError_Unsupported value)? unsupported,
  }) {
    return http?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(StackError_InvalidCredentials value)? invalidCredentials,
    TResult Function(StackError_Auth value)? auth,
    TResult Function(StackError_PendingAgreements value)? pendingAgreements,
    TResult Function(StackError_Http value)? http,
    TResult Function(StackError_Decode value)? decode,
    TResult Function(StackError_Network value)? network,
    TResult Function(StackError_Unsupported value)? unsupported,
    required TResult orElse(),
  }) {
    if (http != null) {
      return http(this);
    }
    return orElse();
  }
}

abstract class StackError_Http extends StackError {
  const factory StackError_Http({
    required final int status,
    required final String message,
  }) = _$StackError_HttpImpl;
  const StackError_Http._() : super._();

  int get status;
  @override
  String get message;

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$StackError_HttpImplCopyWith<_$StackError_HttpImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$StackError_DecodeImplCopyWith<$Res>
    implements $StackErrorCopyWith<$Res> {
  factory _$$StackError_DecodeImplCopyWith(
    _$StackError_DecodeImpl value,
    $Res Function(_$StackError_DecodeImpl) then,
  ) = __$$StackError_DecodeImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$StackError_DecodeImplCopyWithImpl<$Res>
    extends _$StackErrorCopyWithImpl<$Res, _$StackError_DecodeImpl>
    implements _$$StackError_DecodeImplCopyWith<$Res> {
  __$$StackError_DecodeImplCopyWithImpl(
    _$StackError_DecodeImpl _value,
    $Res Function(_$StackError_DecodeImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = null}) {
    return _then(
      _$StackError_DecodeImpl(
        message: null == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$StackError_DecodeImpl extends StackError_Decode {
  const _$StackError_DecodeImpl({required this.message}) : super._();

  @override
  final String message;

  @override
  String toString() {
    return 'StackError.decode(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StackError_DecodeImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$StackError_DecodeImplCopyWith<_$StackError_DecodeImpl> get copyWith =>
      __$$StackError_DecodeImplCopyWithImpl<_$StackError_DecodeImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String message) invalidCredentials,
    required TResult Function(String message) auth,
    required TResult Function(String message) pendingAgreements,
    required TResult Function(int status, String message) http,
    required TResult Function(String message) decode,
    required TResult Function(String message) network,
    required TResult Function(String message) unsupported,
  }) {
    return decode(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String message)? invalidCredentials,
    TResult? Function(String message)? auth,
    TResult? Function(String message)? pendingAgreements,
    TResult? Function(int status, String message)? http,
    TResult? Function(String message)? decode,
    TResult? Function(String message)? network,
    TResult? Function(String message)? unsupported,
  }) {
    return decode?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String message)? invalidCredentials,
    TResult Function(String message)? auth,
    TResult Function(String message)? pendingAgreements,
    TResult Function(int status, String message)? http,
    TResult Function(String message)? decode,
    TResult Function(String message)? network,
    TResult Function(String message)? unsupported,
    required TResult orElse(),
  }) {
    if (decode != null) {
      return decode(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(StackError_InvalidCredentials value)
    invalidCredentials,
    required TResult Function(StackError_Auth value) auth,
    required TResult Function(StackError_PendingAgreements value)
    pendingAgreements,
    required TResult Function(StackError_Http value) http,
    required TResult Function(StackError_Decode value) decode,
    required TResult Function(StackError_Network value) network,
    required TResult Function(StackError_Unsupported value) unsupported,
  }) {
    return decode(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(StackError_InvalidCredentials value)? invalidCredentials,
    TResult? Function(StackError_Auth value)? auth,
    TResult? Function(StackError_PendingAgreements value)? pendingAgreements,
    TResult? Function(StackError_Http value)? http,
    TResult? Function(StackError_Decode value)? decode,
    TResult? Function(StackError_Network value)? network,
    TResult? Function(StackError_Unsupported value)? unsupported,
  }) {
    return decode?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(StackError_InvalidCredentials value)? invalidCredentials,
    TResult Function(StackError_Auth value)? auth,
    TResult Function(StackError_PendingAgreements value)? pendingAgreements,
    TResult Function(StackError_Http value)? http,
    TResult Function(StackError_Decode value)? decode,
    TResult Function(StackError_Network value)? network,
    TResult Function(StackError_Unsupported value)? unsupported,
    required TResult orElse(),
  }) {
    if (decode != null) {
      return decode(this);
    }
    return orElse();
  }
}

abstract class StackError_Decode extends StackError {
  const factory StackError_Decode({required final String message}) =
      _$StackError_DecodeImpl;
  const StackError_Decode._() : super._();

  @override
  String get message;

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$StackError_DecodeImplCopyWith<_$StackError_DecodeImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$StackError_NetworkImplCopyWith<$Res>
    implements $StackErrorCopyWith<$Res> {
  factory _$$StackError_NetworkImplCopyWith(
    _$StackError_NetworkImpl value,
    $Res Function(_$StackError_NetworkImpl) then,
  ) = __$$StackError_NetworkImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$StackError_NetworkImplCopyWithImpl<$Res>
    extends _$StackErrorCopyWithImpl<$Res, _$StackError_NetworkImpl>
    implements _$$StackError_NetworkImplCopyWith<$Res> {
  __$$StackError_NetworkImplCopyWithImpl(
    _$StackError_NetworkImpl _value,
    $Res Function(_$StackError_NetworkImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = null}) {
    return _then(
      _$StackError_NetworkImpl(
        message: null == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$StackError_NetworkImpl extends StackError_Network {
  const _$StackError_NetworkImpl({required this.message}) : super._();

  @override
  final String message;

  @override
  String toString() {
    return 'StackError.network(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StackError_NetworkImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$StackError_NetworkImplCopyWith<_$StackError_NetworkImpl> get copyWith =>
      __$$StackError_NetworkImplCopyWithImpl<_$StackError_NetworkImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String message) invalidCredentials,
    required TResult Function(String message) auth,
    required TResult Function(String message) pendingAgreements,
    required TResult Function(int status, String message) http,
    required TResult Function(String message) decode,
    required TResult Function(String message) network,
    required TResult Function(String message) unsupported,
  }) {
    return network(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String message)? invalidCredentials,
    TResult? Function(String message)? auth,
    TResult? Function(String message)? pendingAgreements,
    TResult? Function(int status, String message)? http,
    TResult? Function(String message)? decode,
    TResult? Function(String message)? network,
    TResult? Function(String message)? unsupported,
  }) {
    return network?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String message)? invalidCredentials,
    TResult Function(String message)? auth,
    TResult Function(String message)? pendingAgreements,
    TResult Function(int status, String message)? http,
    TResult Function(String message)? decode,
    TResult Function(String message)? network,
    TResult Function(String message)? unsupported,
    required TResult orElse(),
  }) {
    if (network != null) {
      return network(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(StackError_InvalidCredentials value)
    invalidCredentials,
    required TResult Function(StackError_Auth value) auth,
    required TResult Function(StackError_PendingAgreements value)
    pendingAgreements,
    required TResult Function(StackError_Http value) http,
    required TResult Function(StackError_Decode value) decode,
    required TResult Function(StackError_Network value) network,
    required TResult Function(StackError_Unsupported value) unsupported,
  }) {
    return network(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(StackError_InvalidCredentials value)? invalidCredentials,
    TResult? Function(StackError_Auth value)? auth,
    TResult? Function(StackError_PendingAgreements value)? pendingAgreements,
    TResult? Function(StackError_Http value)? http,
    TResult? Function(StackError_Decode value)? decode,
    TResult? Function(StackError_Network value)? network,
    TResult? Function(StackError_Unsupported value)? unsupported,
  }) {
    return network?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(StackError_InvalidCredentials value)? invalidCredentials,
    TResult Function(StackError_Auth value)? auth,
    TResult Function(StackError_PendingAgreements value)? pendingAgreements,
    TResult Function(StackError_Http value)? http,
    TResult Function(StackError_Decode value)? decode,
    TResult Function(StackError_Network value)? network,
    TResult Function(StackError_Unsupported value)? unsupported,
    required TResult orElse(),
  }) {
    if (network != null) {
      return network(this);
    }
    return orElse();
  }
}

abstract class StackError_Network extends StackError {
  const factory StackError_Network({required final String message}) =
      _$StackError_NetworkImpl;
  const StackError_Network._() : super._();

  @override
  String get message;

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$StackError_NetworkImplCopyWith<_$StackError_NetworkImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$StackError_UnsupportedImplCopyWith<$Res>
    implements $StackErrorCopyWith<$Res> {
  factory _$$StackError_UnsupportedImplCopyWith(
    _$StackError_UnsupportedImpl value,
    $Res Function(_$StackError_UnsupportedImpl) then,
  ) = __$$StackError_UnsupportedImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$StackError_UnsupportedImplCopyWithImpl<$Res>
    extends _$StackErrorCopyWithImpl<$Res, _$StackError_UnsupportedImpl>
    implements _$$StackError_UnsupportedImplCopyWith<$Res> {
  __$$StackError_UnsupportedImplCopyWithImpl(
    _$StackError_UnsupportedImpl _value,
    $Res Function(_$StackError_UnsupportedImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? message = null}) {
    return _then(
      _$StackError_UnsupportedImpl(
        message: null == message
            ? _value.message
            : message // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$StackError_UnsupportedImpl extends StackError_Unsupported {
  const _$StackError_UnsupportedImpl({required this.message}) : super._();

  @override
  final String message;

  @override
  String toString() {
    return 'StackError.unsupported(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StackError_UnsupportedImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$StackError_UnsupportedImplCopyWith<_$StackError_UnsupportedImpl>
  get copyWith =>
      __$$StackError_UnsupportedImplCopyWithImpl<_$StackError_UnsupportedImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String message) invalidCredentials,
    required TResult Function(String message) auth,
    required TResult Function(String message) pendingAgreements,
    required TResult Function(int status, String message) http,
    required TResult Function(String message) decode,
    required TResult Function(String message) network,
    required TResult Function(String message) unsupported,
  }) {
    return unsupported(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String message)? invalidCredentials,
    TResult? Function(String message)? auth,
    TResult? Function(String message)? pendingAgreements,
    TResult? Function(int status, String message)? http,
    TResult? Function(String message)? decode,
    TResult? Function(String message)? network,
    TResult? Function(String message)? unsupported,
  }) {
    return unsupported?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String message)? invalidCredentials,
    TResult Function(String message)? auth,
    TResult Function(String message)? pendingAgreements,
    TResult Function(int status, String message)? http,
    TResult Function(String message)? decode,
    TResult Function(String message)? network,
    TResult Function(String message)? unsupported,
    required TResult orElse(),
  }) {
    if (unsupported != null) {
      return unsupported(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(StackError_InvalidCredentials value)
    invalidCredentials,
    required TResult Function(StackError_Auth value) auth,
    required TResult Function(StackError_PendingAgreements value)
    pendingAgreements,
    required TResult Function(StackError_Http value) http,
    required TResult Function(StackError_Decode value) decode,
    required TResult Function(StackError_Network value) network,
    required TResult Function(StackError_Unsupported value) unsupported,
  }) {
    return unsupported(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(StackError_InvalidCredentials value)? invalidCredentials,
    TResult? Function(StackError_Auth value)? auth,
    TResult? Function(StackError_PendingAgreements value)? pendingAgreements,
    TResult? Function(StackError_Http value)? http,
    TResult? Function(StackError_Decode value)? decode,
    TResult? Function(StackError_Network value)? network,
    TResult? Function(StackError_Unsupported value)? unsupported,
  }) {
    return unsupported?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(StackError_InvalidCredentials value)? invalidCredentials,
    TResult Function(StackError_Auth value)? auth,
    TResult Function(StackError_PendingAgreements value)? pendingAgreements,
    TResult Function(StackError_Http value)? http,
    TResult Function(StackError_Decode value)? decode,
    TResult Function(StackError_Network value)? network,
    TResult Function(StackError_Unsupported value)? unsupported,
    required TResult orElse(),
  }) {
    if (unsupported != null) {
      return unsupported(this);
    }
    return orElse();
  }
}

abstract class StackError_Unsupported extends StackError {
  const factory StackError_Unsupported({required final String message}) =
      _$StackError_UnsupportedImpl;
  const StackError_Unsupported._() : super._();

  @override
  String get message;

  /// Create a copy of StackError
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$StackError_UnsupportedImplCopyWith<_$StackError_UnsupportedImpl>
  get copyWith => throw _privateConstructorUsedError;
}
