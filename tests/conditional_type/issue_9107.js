type KeyType<T> = T extends $ReadOnlyArray<mixed> ? number : string;
type PropType<T, K> = T extends $ReadOnlyArray<infer V> ? V : T[K];

declare function set(): void;
declare function set<K1>(
  prop1: K1,
  prop2: KeyType<PropType<$ReadOnlyArray<{}>, K1>>,
): void;

declare var index: number;
declare var key: string;
set(index, key); // ok
