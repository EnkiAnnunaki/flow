"use strict";(self.webpackChunknew_website=self.webpackChunknew_website||[]).push([[5789],{5789:(e,n,t)=>{t.r(n),t.d(n,{assets:()=>d,contentTitle:()=>r,default:()=>l,frontMatter:()=>o,metadata:()=>i,toc:()=>m});var a=t(87462),p=(t(67294),t(3905));t(45475);const o={title:"Mapped Types",slug:"/types/mapped-types"},r=void 0,i={unversionedId:"types/mapped-types",id:"types/mapped-types",title:"Mapped Types",description:"Flow's mapped types allow you to transform object types. They are useful for modeling complex runtime operations over objects.",source:"@site/docs/types/mapped-types.md",sourceDirName:"types",slug:"/types/mapped-types",permalink:"/en/docs/types/mapped-types",draft:!1,editUrl:"https://github.com/facebook/flow/edit/main/website/docs/types/mapped-types.md",tags:[],version:"current",frontMatter:{title:"Mapped Types",slug:"/types/mapped-types"},sidebar:"docsSidebar",previous:{title:"Conditional Types",permalink:"/en/docs/types/conditional"},next:{title:"Type Guards",permalink:"/en/docs/types/type-guards"}},d={},m=[{value:"Basic Usage",id:"toc-basic-usage",level:2},{value:"Mapped Type Sources",id:"toc-mapped-type-sources",level:2},{value:"Distributive Mapped Types",id:"toc-distributive-mapped-types",level:2},{value:"Property Modifiers",id:"toc-property-modifiers",level:2},{value:"Adoption",id:"toc-adoption",level:2}],s={toc:m};function l(e){let{components:n,...t}=e;return(0,p.mdx)("wrapper",(0,a.Z)({},s,t,{components:n,mdxType:"MDXLayout"}),(0,p.mdx)("p",null,"Flow's mapped types allow you to transform object types. They are useful for modeling complex runtime operations over objects."),(0,p.mdx)("h2",{id:"toc-basic-usage"},"Basic Usage"),(0,p.mdx)("p",null,"Mapped Types have syntax similar to indexed object types but use the ",(0,p.mdx)("inlineCode",{parentName:"p"},"in")," keyword:"),(0,p.mdx)("pre",null,(0,p.mdx)("code",{parentName:"pre",className:"language-flow",metastring:"[]","[]":!0},"type O = {foo: number, bar: string};\n\ntype Methodify<T> = () => T;\n\ntype MappedType = {[key in keyof O]: Methodify<O[key]>};\n")),(0,p.mdx)("p",null,"In this example, ",(0,p.mdx)("inlineCode",{parentName:"p"},"MappedType")," has all of the keys from ",(0,p.mdx)("inlineCode",{parentName:"p"},"O")," with all of the value types transformed by\n",(0,p.mdx)("inlineCode",{parentName:"p"},"Methoditfy<O[key]>"),". The ",(0,p.mdx)("inlineCode",{parentName:"p"},"key")," variable is substituted for each key in ",(0,p.mdx)("inlineCode",{parentName:"p"},"O")," when creating the property, so\nthis type evaluates to:"),(0,p.mdx)("pre",null,(0,p.mdx)("code",{parentName:"pre"},"{\n  foo: Methodify<O['foo']>,\n  bar: Methodify<O['bar']>,\n}\n= {\n  foo: () => number,\n  bar: () => string,\n}\n")),(0,p.mdx)("h2",{id:"toc-mapped-type-sources"},"Mapped Type Sources"),(0,p.mdx)("p",null,"We call the type that comes after the ",(0,p.mdx)("inlineCode",{parentName:"p"},"in")," keyword the ",(0,p.mdx)("em",{parentName:"p"},"source")," of the mapped type. The source of\na mapped type must be a subtype of ",(0,p.mdx)("inlineCode",{parentName:"p"},"string | number | symbol"),":"),(0,p.mdx)("pre",null,(0,p.mdx)("code",{parentName:"pre",className:"language-flow",metastring:'[{"startLine":1,"startColumn":28,"endLine":1,"endColumn":34,"description":"Cannot instantiate mapped type [1] because boolean [2] is incompatible with `string | number | symbol`, so it cannot be used to generate keys for mapped type [1]. [incompatible-type]"}]','[{"startLine":1,"startColumn":28,"endLine":1,"endColumn":34,"description":"Cannot':!0,instantiate:!0,mapped:!0,type:!0,"[1]":!0,because:!0,boolean:!0,"[2]":!0,is:!0,incompatible:!0,with:!0,"`string":!0,"|":!0,number:!0,"symbol`,":!0,so:!0,it:!0,cannot:!0,be:!0,used:!0,to:!0,generate:!0,keys:!0,for:!0,"[1].":!0,'[incompatible-type]"}]':!0},"type MappedType = {[key in boolean]: number}; // ERROR!\n")),(0,p.mdx)("p",null,"Typically, you'll want to create a mapped type based on another object type. In this case, you\nshould write your mapped type using an inline ",(0,p.mdx)("inlineCode",{parentName:"p"},"keyof"),":"),(0,p.mdx)("pre",null,(0,p.mdx)("code",{parentName:"pre",className:"language-flow",metastring:"[]","[]":!0},"type GetterOf<T> = () => T;\ntype Obj = {foo: number, bar: string};\ntype MappedObj = {[key in keyof Obj]: GetterOf<Obj[key]>};\n")),(0,p.mdx)("blockquote",null,(0,p.mdx)("p",{parentName:"blockquote"},"NOTE: ",(0,p.mdx)("inlineCode",{parentName:"p"},"keyof")," only works inline in mapped types for now. Full support for ",(0,p.mdx)("inlineCode",{parentName:"p"},"keyof")," is not yet available.")),(0,p.mdx)("p",null,"But you do not need to use an object to generate a mapped type. You can also use a union of string\nliteral types to represent the keys of an object type:"),(0,p.mdx)("pre",null,(0,p.mdx)("code",{parentName:"pre",className:"language-flow",metastring:"[]","[]":!0},"type Union = 'foo' | 'bar' | 'baz';\ntype MappedType = {[key in Union]: number};\n// = {foo: number, bar: number, baz: number};\n")),(0,p.mdx)("p",null,"Importantly, when using string literals the union is collapsed into a ",(0,p.mdx)("em",{parentName:"p"},"single object type"),":"),(0,p.mdx)("pre",null,(0,p.mdx)("code",{parentName:"pre",className:"language-flow",metastring:"[]","[]":!0},"type MappedTypeFromKeys<Keys: string> = {[key in Keys]: number};\ntype MappedFooAndBar = MappedTypeFromKeys<'foo' | 'bar'>;\n// = {foo: number, bar: number}, not {foo: number} | {bar: number}\n")),(0,p.mdx)("p",null,"If you use a type like ",(0,p.mdx)("inlineCode",{parentName:"p"},"number")," or ",(0,p.mdx)("inlineCode",{parentName:"p"},"string")," in the source of your mapped type then Flow will create\nan indexer:"),(0,p.mdx)("pre",null,(0,p.mdx)("code",{parentName:"pre",className:"language-flow",metastring:"[]","[]":!0},"type MappedTypeFromKeys<Keys: string> = {[key in Keys]: number};\ntype MappedFooAndBarWithIndexer = MappedTypeFromKeys<'foo' | 'bar' | string>;\n// = {foo: number, bar: number, [string]: number}\n")),(0,p.mdx)("h2",{id:"toc-distributive-mapped-types"},"Distributive Mapped Types"),(0,p.mdx)("p",null,"When the mapped type uses an inline ",(0,p.mdx)("inlineCode",{parentName:"p"},"keyof")," or a type parameter bound by a ",(0,p.mdx)("inlineCode",{parentName:"p"},"$Keys"),"\nFlow will distribute the mapped type over unions of object types."),(0,p.mdx)("p",null,"For example:"),(0,p.mdx)("pre",null,(0,p.mdx)("code",{parentName:"pre",className:"language-flow",metastring:"[]","[]":!0},"// This mapped type uses keyof inline\ntype MakeAllValuesNumber<O: {...}> = {[key in keyof O]: number};\ntype ObjWithFoo = {foo: string};\ntype ObjWithBar = {bar: string};\n\ntype DistributedMappedType = MakeAllValuesNumber<\n  | ObjWithFoo\n  | ObjWithBar\n>; // = {foo: number} | {bar: number};\n\n// This mapped type uses a type parameter bound by $Keys\ntype Pick<O: {...}, Keys: $Keys<O>> = {[key in Keys]: O[key]};\ntype O1 = {foo: number, bar: number};\ntype O2 = {bar: string, baz: number};\ntype PickBar = Pick<O1 | O2, 'bar'>; // = {bar: number} | {bar: string};\n")),(0,p.mdx)("p",null,"Distributive mapped types will also distribute over ",(0,p.mdx)("inlineCode",{parentName:"p"},"null")," and ",(0,p.mdx)("inlineCode",{parentName:"p"},"undefined"),":"),(0,p.mdx)("pre",null,(0,p.mdx)("code",{parentName:"pre",className:"language-flow",metastring:"[]","[]":!0},"type Distributive<O: ?{...}> = {[key in keyof O]: O[key]};\ntype Obj = {foo: number};\ntype MaybeMapped = Distributive<?Obj>;// = ?{foo: number}\n(null: MaybeMapped); // OK\n(undefined: MaybeMapped); // OK\n({foo: 3}: MaybeMapped); // OK\n")),(0,p.mdx)("h2",{id:"toc-property-modifiers"},"Property Modifiers"),(0,p.mdx)("p",null,"You can also add ",(0,p.mdx)("inlineCode",{parentName:"p"},"+")," or ",(0,p.mdx)("inlineCode",{parentName:"p"},"-")," variance modifiers and the optionality modifier ",(0,p.mdx)("inlineCode",{parentName:"p"},"?")," in mapped types:"),(0,p.mdx)("pre",null,(0,p.mdx)("code",{parentName:"pre",className:"language-flow",metastring:"[]","[]":!0},"type O = {foo: number, bar: string}\ntype ReadOnlyPartialO = {+[key in keyof O]?: O[key]}; // = {+foo?: number, +bar?: string};\n")),(0,p.mdx)("p",null,"When no variance nor optionality modifiers are provided and the mapped type is distributive,\nthe variance and optionality are determined by the input object:"),(0,p.mdx)("pre",null,(0,p.mdx)("code",{parentName:"pre",className:"language-flow",metastring:"[]","[]":!0},"type O = {+foo: number, bar?: string};\ntype Mapped = {[key in keyof O]: O[key]}; // = {+foo: number, bar?: string}\n")),(0,p.mdx)("p",null,"Otherwise, the properties are read-write and required when no property modifiers are present:"),(0,p.mdx)("pre",null,(0,p.mdx)("code",{parentName:"pre",className:"language-flow",metastring:"[]","[]":!0},"type Union = 'foo' | 'bar' | 'baz';\ntype MappedType = {[key in Union]: number};\n// = {foo: number, bar: number, baz: number};\n")),(0,p.mdx)("blockquote",null,(0,p.mdx)("p",{parentName:"blockquote"},"NOTE: Flow does not yet support removing variance or optionality modifiers.")),(0,p.mdx)("h2",{id:"toc-adoption"},"Adoption"),(0,p.mdx)("p",null,"To use mapped types, you need to upgrade your infrastructure so that it supports the syntax:"),(0,p.mdx)("ul",null,(0,p.mdx)("li",{parentName:"ul"},(0,p.mdx)("inlineCode",{parentName:"li"},"flow")," and ",(0,p.mdx)("inlineCode",{parentName:"li"},"flow-parser"),": 0.210.0. Between v0.210.0 to v0.211.1, you need to explicitly enable it in your .flowconfig, under the ",(0,p.mdx)("inlineCode",{parentName:"li"},"[options]")," heading, add ",(0,p.mdx)("inlineCode",{parentName:"li"},"mapped_type=true"),"."),(0,p.mdx)("li",{parentName:"ul"},(0,p.mdx)("inlineCode",{parentName:"li"},"prettier"),": 3"),(0,p.mdx)("li",{parentName:"ul"},(0,p.mdx)("inlineCode",{parentName:"li"},"babel")," with ",(0,p.mdx)("inlineCode",{parentName:"li"},"babel-plugin-syntax-hermes-parser"),". See ",(0,p.mdx)("a",{parentName:"li",href:"../../tools/babel/"},"our Babel guide")," for setup instructions."),(0,p.mdx)("li",{parentName:"ul"},(0,p.mdx)("inlineCode",{parentName:"li"},"eslint")," with ",(0,p.mdx)("inlineCode",{parentName:"li"},"hermes-eslint"),". See ",(0,p.mdx)("a",{parentName:"li",href:"../../tools/eslint/"},"our ESLint guide")," for setup instructions.")))}l.isMDXComponent=!0}}]);