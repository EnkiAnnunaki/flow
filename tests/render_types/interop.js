//@flow
import * as React from 'react';

function Foo(): React.Node {}

component Bar() renders React.Element<typeof Foo> {
  return <Foo />; // OK
}

(<Bar />) as renders React.Element<typeof Foo>; // OK

function Baz(): renders React.Element<typeof Bar> {
  return <Bar />;
} // OK
component Qux() {
  return null;
}
(<Baz />) as renders React.Element<typeof Bar>; // OK
(<Baz />) as renders React.Element<typeof Qux>; // ERROR

function RendersBaz(): renders React.Element<typeof Baz> {
  return <Baz />;
}
(<RendersBaz />) as renders React.Element<typeof Bar>; // OK
(<RendersBaz />) as renders React.Element<typeof Qux>; // ERROR

function LongerChain(): renders React.Element<typeof RendersBaz> {
  return <RendersBaz />;
}
(<LongerChain />) as renders React.Element<typeof Bar>; // OK
(<LongerChain />) as renders React.Element<typeof Qux>; // ERROR
