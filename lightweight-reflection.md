Lightweight Scala Reflection and why Dotty needs TypeTags reimplemented
=======================================================================

[Type tags](https://docs.scala-lang.org/overviews/reflection/typetags-manifests.html) are one of the most attractive features of Scala.

They allow you to overcome type erasure. They allow you to check equality subtyping and equality. Here is an example:

```scala
import scala.reflect.runtime.universe._

def check[T : TypeTag](v: T) = {
  val tag = implicitly[TypeTag[T]].tpe
  println(s"//↳value $v is of type $tag")

  if (tag =:= typeTag[Right[Int, Int]].tpe) {
    println(s"//↳value $v has exact type of Right[Int, Int]")
  }

  if (tag <:< typeTag[Either[Int, Object]].tpe) {
    println(s"//↳value $v is a subtype of Either[Int, Object]: $tag")
  }
}

check(Right[Int, Int](1))
//↳value Right(1) is of type scala.util.Right[Int,Int]
//↳value Right(1) has exact type of Right[Int, Int]

check(Right[Nothing, Int](1))
//↳value Right(1) is of type scala.util.Right[Nothing,Int]

check(Right("xxx"))
//↳value Right(xxx) is of type scala.util.Right[Nothing,String]
//↳value Right(xxx) is a subtype of Either[Int, Object]: scala.util.Right[Nothing,String]
```

Type tags let you do lot more. Essentially, `scala-reflect` and TypeTag machinery are chunks of internal compiler data structures and tools exposed directly to the user. Though the most important operations are identity check (`=:=`) and subtype check (`<:<`).

`TypeTag` concept is a cornerstone for our project --- [distage](https://izumi.7mind.io/latest/release/doc/distage/index.html) --- smart module system for Scala, featuring a solver and a dependency injection mechanism.

Type tags allows us to turn an arbitrary function into an entity we can introspect at both compile time and run time:

```scala
import com.github.pshirshov.izumi.distage.model.providers.ProviderMagnet

val fn = ProviderMagnet {
    (x: Int, y: String) => (x, y)
  }.get

println(s"//↳function arity: ${fn.arity}")
//↳function arity: 2
println(s"//↳function signature: ${fn.argTypes}")
//↳function signature: List(Int, String)
println(s"//↳function return type: ${fn.ret}")
//↳function return type: (Int, String)
println(s"//↳function application: ${fn.fun.apply(Seq(1, "hi"))}")
//↳function application: (1,hi)
```

Unfortunately, current TypeTag implementation is flawed:

- They [do not support](https://github.com/scala/bug/issues/7686) higher-kinded types,
- They suffer many [concurrency issues](https://github.com/scala/bug/issues/10766) and it's not so trivial to fix them. In our case TypeTags were occasionaly failing subtype checks (`child <:< parent`) during `scala-reflect` initialization even if we synchronize on literally everything,
- `scala-reflect` needs *seconds* to initialize.

Moreover, it's still unclear if Scala 3 will support TypeTag concept or not.
Some people say it's too hard and recommend to write a custom macro to replace TypeTags for in Scala 3 / Dotty when it's necessary.

So, we tried to implement our own lightweight TypeTag replacement with a macro. It's doable. It works. Though it's overcomplicated and there are many subtle discrepancies between Scala model and our model. So we still hope that Dotty team will consider supporint TypeTags in Scala 3. Currently our implementation supports Scala 2.12/2.13 though it's possible to port it to Dotty and we are going to do it in foreseeable future.

## What we need

We want to have the following features:

- An ability to check if two types are identical (`=:=`),
- An ability to check if one type is a subtype of another (`<:<`),
- An ability to combine type tags at runtime `Tag[List[_]].combine(Tag[Int])`.

## Starting point: undefined behavior in Scalac helps to circumvent TypeTag limitations

Unfortunately, there is no way in Scala to request a TypeTag for an unapplied type (or a "type lambda").
The model itself can express it but there is no syntax for that.

So, this doesn't work:

```scala
type T[K] = Either[K, Unit]
typeTag[T] // fail
```

Fortunately there are two workarounds for that.


### Undefined behavior for rescue: simple materializer

For some reason `scalac` ignores type parameters passed to a type within macro definition:

```scala
import scala.language.experimental.macros
import scala.reflect.macros.blackbox
import scala.reflect.runtime.universe._

trait LightTypeTag { /*TODO*/ }

def makeTag[T: c.WeakTypeTag](c: blackbox.Context): c.Expr[LightTypeTag] = {
  import c.universe._
  val tpe = implicitly[WeakTypeTag[T]].tpe
  println(("type tag", tpe.etaExpand))
  println(("unbound type parameters", tpe.typeParams))
  println(("result type", tpe.etaExpand.resultType.dealias))
  c.Expr[LightTypeTag](q"null")
}

def materialize1[T[_]]: LightTypeTag = macro makeTag[T[Nothing]]

type T0[K, V] = Either[K, V]
type T1[K1] = T0[K1, Unit]

materialize1[T1]
```

This example prints

```
(type tag,[K1]T1[K1])
(unbound type parameters,List(type K1))
(result type,scala.util.Either[K1,Unit])
```

Now we may see that:

- `Nothing` has disappeared out of `T[Nothing]`,
- We've successfully circumvented Scala's syntactic limitations and got a weak type tag for our unapplied `type Example[K]`! It's an undefined but logical and very useful behaviour,
- Scala can expand all the nested lambdas into a single lambda.

### Better approach

Previous trick would require us to manually write a custom materializer for every kind we want to get our type tags for. So there is another approach which is more useful for practical usage.

We wrap our type lambda into a structural refinement of a type:

```scala
trait HKTag[T] {
  // ...
}

type Wrapped = HKTag[{ type Arg[A] = K[A] }]
```

Now we got rid of these damn type arguments and may analyse different `Wrapped` types uniformly.
This is outside of the scope of this post, you may find completed and working example in [distage repository](https://github.com/7mind/izumi/tree/403bbf669fd2ab6924564f821cb52c459c3be082/fundamentals/fundamentals-reflection/src/main/scala/com/github/pshirshov/izumi/fundamentals/reflection)

## Designing data model

We want to use a macro to statically generate non-ambigious type identifiers. And we have the following Scala features to support:

- [Parameterized types](https://docs.scala-lang.org/tour/generic-classes.html) (Generics),
- [Unapplied types](http://eed3si9n.com/herding-cats/Kinds.html) (type lambdas, higher-kinded types),
- [Compound types](https://docs.scala-lang.org/tour/compound-types.html):  `val v: Type1 with Type2`,
- [Structural types](https://docs.scala-lang.org/style/types.html#structural-types): `val v: {def repr(a: Int): String}`,
- [Path-dependent types](https://docs.scala-lang.org/tour/inner-classes.html): `val a: b.T`. Actually it's very hard to provide comprehensive support for PDTs but we may do it to some extent,
- [Variances](https://docs.scala-lang.org/tour/variances.html): `trait T[+A]`,
- [Type bounds](https://docs.scala-lang.org/tour/upper-type-bounds.html): `trait T1[K <: T0]`


Essentially, we have two primary forms of our types, applied and unapplied. So, let's encode this:

```scala
sealed trait LightTypeTag
sealed trait AppliedReference extends LightTypeTag
sealed trait AppliedNamedReference extends LightTypeTag
```

Now we may define helper structures, describing type bounds and variance:

```scala
sealed trait Boundaries
object Boundaries {
  case class Defined(bottom: LightTypeTag, top: LightTypeTag) extends Boundaries
  case object Empty extends Boundaries
}

sealed trait Variance
object Variance {
  case object Invariant extends Variance
  case object Contravariant extends Variance
  case object Covariant extends Variance
}
```

`Boundaries.Empty` is an optimization for default boundaries of `>: Nothing <: Any`

**Gotcha**: type bounds in Scala are recursive! So it's pretty hard to restore them properly, but we may detect recursive and loose the boundaries appropriately.

So, we will identify nongeneric types using their fully qualified names. A type may have a prefix (in case it's a PDT) and type boundaries (in case it's an abstract type parameter):

```scala
case class NameReference(ref: String, boundaries: Boundaries, prefix: Option[AppliedReference]) extends AppliedNamedReference
```

Now we may define reference for a generic:

```scala
case class TypeParam(ref: LightTypeTag, variance: Variance)
case class FullReference(ref: String, parameters: List[TypeParam],  prefix: Option[AppliedReference]) extends AppliedNamedReference
```

And now we may define a type lambda:

```scala
case class Lambda(input: List[LambdaParameter], output: LightTypeTag) extends LightTypeTag
case class LambdaParameter(name: String)
```

The compound type is simple:

```scala
case class IntersectionReference(refs: Set[AppliedNamedReference]) extends AppliedReference
```

And here comes structural type:

```scala
sealed trait RefinementDecl
object RefinementDecl {
  case class Signature(name: String, input: List[AppliedReference], output: AppliedReference) extends RefinementDecl
  case class TypeMember(name: String, ref: LightTypeTag) extends RefinementDecl
}

case class Refinement(reference: AppliedReference, decls: Set[RefinementDecl]) extends AppliedReference
```

This model is not completely correct (e.g. it's better to use a `NonEmptyList` in `FullReference`, etc, etc). Though it may do the job.

Feel free to propose improvements.

## The logic behind

### Compile time: type lambdas and kind projector

TODO

### Runtime: type tag combinators

TODO

### Runtime: subtype checks

TODO

## The rest of the damn Owl

I provided some basic insights into the problem. In case you wish to look at the full implementation, you may find it [in our repository](https://github.com/7mind/izumi/tree/feature/light-type-tags-wip0/fundamentals/fundamentals-reflection/src/main/scala/com/github/pshirshov/izumi/fundamentals/reflection/macrortti). It has 2K+ LoC and has all the necessary features implemented. Also there are some logging facilities allowing you to get a detailed log of what happens during subtype checks.

We would welcome any contributions into our library and feel free to use this post and our code as a starting point for your own implementation.

![Draw the rest of the damn Owl](owl.jpg)

## Conclusion

It's possible to implement `scala-reflect`-like features with a macro. Though it's a challenging task.
At the same time for many enterprise developers good reflection is one of the most attractive Scala features.
It allows us to have many positive traits of dynamic languages without giving up on type safety.

I wrote this post with a hope that it may help to convince Dotty team to re-implement reflection in Scala 3.
In case it wouldn't, we, [Septimal Mind](https://7mind.io) will try to maintain our solution and port it to Dotty,
but, as I mentioned earlier, it's not possible to make it completely correct.
