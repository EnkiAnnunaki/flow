import {Foo, type RendersFoo} from './export'
import * as React from 'react';
(<Foo />: RendersFoo); // OK

component Bar() { return null }
(<Foo />: renders React.Element<typeof Bar>); // ERROR
(<Bar />: renders React.Element<typeof Foo>); // ERROR
