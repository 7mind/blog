Lightweight Scala Reflection and why Dotty needs TypeTags reimplemented
=======================================================================

[TypeTags](https://docs.scala-lang.org/overviews/reflection/typetags-manifests.html) are one of the most attractive features of Scala.

They allow you to overcome type erasure. They allow you to check equality subtyping and equality.

```scala
import scala.reflect.runtime.universe._
scala> val tag = typeTag[Either[String, Int]]
scala> tag.tpe.typeArgs
res0: List[reflect.runtime.universe.Type] = List(String, Int)
scala> tag.tpe.typeArgs.head =:= typeTag[String].tpe
res1: Boolean = true
scala> tag.tpe.typeArgs.last <:< typeTag[Any].tpe
res5: Boolean = true
```

And you may do lot more with them. Essentially, `scala-reflect` and TypeTag machinery are chunks of internal compiler data structures and tools exposed directly to the user.

TypeTag is a cornerstone concept for our project --- [distage](https://izumi.7mind.io/latest/release/doc/distage/index.html) --- smart module system for Scala, featuring a solver and a dependency injection mechanism.

TypeTags allows us to turn an arbitrary function into an entity we can introspect at runtime:

```scala
import com.github.pshirshov.izumi.distage.model.providers.ProviderMagnet

val fn = ProviderMagnet {
    (x: Int, y: String) => (x, y)
  }.get

println(("function arity", fn.arity))
println(("function signature", fn.argTypes))
println(("function return type", fn.ret))
println(("function application", fn.fun.apply(Seq(1, "hi"))))
```

The example above produces the following output:

```
(function arity,2)
(function signature,List(Int, String))
(function return type,(Int, String))
(function application,(1,hi))
```

Unfortunately, current TypeTag implementation is flawed:

- They [do not support](https://github.com/scala/bug/issues/7686) higher-kinded types
- They suffer many [concurrency issues](https://github.com/scala/bug/issues/10766) and it's not so trivial to fix them. In our case TypeTags were occasionaly failing subtype checks (`child <:< parent`) during `scala-reflect` initialization even if we synchronize on literally everything.
- `scala-reflect` needs *seconds* to initialize

Moreover, it's still unclear if Scala 3 will support TypeTag concept or not.
Some people say it's too hard and recommend to write a custom macro to replace TypeTags for in Scala 3 / Dotty when it's necessary.

So, we tried to implement our own lightweight TypeTag replacement with a macro. It's doable. It works. Though it's overcomplicated and there are many subtle discrepancies between Scala model and our model. So we still hope that Dotty team will consider supporint TypeTags in Scala 3. Currently our implementation supports Scala 2.12/2.13 though it's possible to port it to Dotty and we are going to do it in foreseeable future.

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

type Example[K] = Either[K, Unit]

materialize1[Example]
```

This example prints

```
(type tag,[K]Example[K])
(unbound type parameters,List(type K))
(result type,scala.util.Either[K,Unit])
```

Now we may see that:

- `Nothing` has disappeared out of `T[Nothing]`,
- We've successfully circumvented Scala's syntactic limitations and got a weak type tag for our unapplied `type Example[K]`!

It's an undefined but logical and very useful behaviour.

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

## The rest of the damn Owl

![owl](owl.jpg)
