import 'package:equatable/equatable.dart';

/// Returns a `hashCode` for [props].
int mapPropsToHashCode(Iterable<Object?>? props) {
  var hash = 0;
  if (props != null) {
    // Avoid the generic fold callback on this hot path.
    for (final prop in props) {
      hash = _combine(hash, prop);
    }
  }
  return _finish(hash);
}

/// Determines whether two lists ([a] and [b]) are equal.
// See https://github.com/felangel/equatable/issues/187.
@pragma('vm:prefer-inline')
bool equals(List<Object?>? a, List<Object?>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return iterableEquals(a, b);
}

/// Determines whether two iterables are equal.
@pragma('vm:prefer-inline')
bool iterableEquals(Iterable<Object?> a, Iterable<Object?> b) {
  if (identical(a, b)) return true;
  // Sets implement Iterable but must compare independent of iteration order.
  // Comparing a Set with an ordered sequence is never value equality.
  if (a is Set<Object?> || b is Set<Object?>) {
    return a is Set<Object?> &&
        b is Set<Object?> &&
        setEquals(a, b);
  }
  // Keep indexed access for lists, but avoid repeated elementAt(i) traversals
  // (and repeated length computation) on other Iterable implementations.
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!objectsEquals(a[i], b[i])) return false;
    }
    return true;
  }

  final iteratorA = a.iterator;
  final iteratorB = b.iterator;
  while (iteratorA.moveNext()) {
    if (!iteratorB.moveNext() ||
        !objectsEquals(iteratorA.current, iteratorB.current)) {
      return false;
    }
  }
  return !iteratorB.moveNext();
}

/// Determines whether two sets are equal.
bool setEquals(Set<Object?> a, Set<Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;

  // Native hash lookup avoids the quadratic scan for ordinary sets.
  // Set.identity and custom Set equality can disagree with objectsEquals,
  // so every candidate must be checked. Each candidate may match only once.
  if (!_requiresDeepMatching(a) && !_requiresDeepMatching(b)) {
    final used = Set<Object?>.identity();
    var allMatched = true;
    for (final element in a) {
      final match = b.lookup(element);
      if ((match == null && !b.contains(element)) ||
          !objectsEquals(element, match) ||
          !used.add(match)) {
        allMatched = false;
        break;
      }
    }
    if (allMatched) return true;
  }

  // Deep equality can match distinct objects with different native hashes.
  // Use one-to-one matching when the native fast path cannot prove equality.
  final unmatched = b.toList();
  for (final element in a) {
    final index = unmatched.indexWhere(
      (value) => objectsEquals(element, value),
    );
    if (index == -1) return false;
    // Order is irrelevant; swap with the last candidate to remove in O(1).
    unmatched[index] = unmatched.last;
    unmatched.removeLast();
  }
  return true;
}

bool _requiresDeepMatching(Set<Object?> values) {
  for (final value in values) {
    if (value is Iterable<Object?> || value is Map<Object?, Object?>) {
      return true;
    }
  }
  return false;
}

/// Determines whether two maps are equal.
bool mapEquals(Map<Object?, Object?> a, Map<Object?, Object?> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    // Reading the value also tests whether a non-null value is present.
    // Only null values need containsKey to distinguish a missing key.
    final otherValue = b[entry.key];
    if (!objectsEquals(entry.value, otherValue) ||
        (otherValue == null && !b.containsKey(entry.key))) {
      return false;
    }
  }
  return true;
}

/// Determines whether two objects are equal.
@pragma('vm:prefer-inline')
bool objectsEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  // Equatable's own == must take precedence even when a subtype is
  // iterable. Comparing it structurally would ignore its custom props.
  if (a is Equatable || b is Equatable) {
    return a is Equatable && b is Equatable && a == b;
  }
  // Sets are unordered: never compare a Set as an ordered Iterable.
  if (a is Set<Object?> || b is Set<Object?>) {
    return a is Set<Object?> &&
        b is Set<Object?> &&
        setEquals(a, b);
  }
  if (a is Iterable<Object?> && b is Iterable<Object?>) {
    return iterableEquals(a, b);
  }
  if (a is Map<Object?, Object?> && b is Map<Object?, Object?>) {
    return mapEquals(a, b);
  }
  return a == b;
}

/// Jenkins Hash Functions
/// https://en.wikipedia.org/wiki/Jenkins_hash_function
int _combine(int hash, Object? object) {
  // Equatable objects can also implement Iterable. Their value semantics
  // come from props, not from their iterator.
  if (object is Equatable) {
    return _combine(hash, object.hashCode);
  }
  if (object is Map) {
    var unorderedHash = 0;
    for (final entry in object.entries) {
      // Map keys are compared by native ==/hashCode (containsKey), unlike
      // map values, which are compared structurally by objectsEquals.
      final entryHash = _finish(
        _combine(_combine(0, entry.key.hashCode), entry.value),
      );
      unorderedHash = 0x1fffffff & (unorderedHash + entryHash);
    }
    return _combine(hash, unorderedHash ^ object.length);
  }
  if (object is Set) {
    var unorderedHash = 0;
    for (final element in object) {
      unorderedHash =
          0x1fffffff & (unorderedHash + _finish(_combine(0, element)));
    }
    return _combine(hash, unorderedHash ^ object.length);
  }
  if (object is Iterable) {
    var length = 0;
    for (final value in object) {
      hash = hash ^ _combine(hash, value);
      length++;
    }
    return hash ^ length;
  }

  hash = 0x1fffffff & (hash + object.hashCode);
  hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
  return hash ^ (hash >> 6);
}

int _finish(int hash) {
  hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
  hash = hash ^ (hash >> 11);
  return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
}

/// Returns a string for [props].
String mapPropsToString(Type runtimeType, List<Object?> props) {
  final buffer = StringBuffer()..write(runtimeType)..write('(');
  for (var index = 0; index < props.length; index++) {
    if (index != 0) buffer.write(', ');
    buffer.write(props[index]);
  }
  buffer.write(')');
  return buffer.toString();
}
