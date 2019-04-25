No More Orphans
=================================

If you've ever created a library in the Scala FP ecosystem, you may have faced some tough choices:

- Should my library support Cats? Or Scalaz? Or both? 
- Should my library be usable without any FP library at all?
- Should I add integrations with `refined`, `enumeratum`, `slick`, `shapeless`, `circe`, `argonaut` or any other popular library?

All choices here come with their set of trade-offs. If you choose to settle on `cats`, a `scalaz` user may be forced to
import shims to use your library. 
If you choose to have no dependencies on an FP lib, your `cats`/`scalaz` users will have to write missing instances and 
integrations themselves! You may choose to provide 'orphan' implicits – implicits defined outside of your types' companion
objects – in separate modules such as `mylib-cats` and `mylib-scalaz`. Unlike implicit instances defined in companion objects,
orphan implicits have to be imported to be picked up by the compiler, your users will be forced to manually find and import
these instances whenever they want to interact with your library!

```scala
import cats.implicits._
import mylib.interop.cats._
```

If your library is foundational to an application, such as a database driver or an effect system, nearly every file in user's
application might have to repeat these magic imports.
Worse still, your library might not even be the only library that exports orphans. The import tax compounds for every 
other library that follows this pattern!

```scala
import otherlib.adapters.cats._
import xyzlib.instances.circe._
// aaaaah!!!
```

User experience suffers proportionally to a library's degree of modularization, the fewer instances are provided
in the core module, the more magic imports are required to use the library.

Is there a way to get rid of these magic imports? Should we eschew integration modules completely and add integrations with every
other library in companion objects right in our core module? That would give most libraries a very heavy dependency footprint,
consisting of libraries that were brought in just to define an instance or two. Forcing the user to depend on every Scala
library out there is not really a good idea. Is there another way? Can we have our cake and eat it too? Well, yeah.

Eliminating dependencies
------------------------

To start with, it's actually a pretty OK idea to depend on every other library out there right in our core module.
We just don't want _our users_ to have to depend on these libraries.

SBT will happily let us add a dependency that _won't_ be passed down to library users, using the `Optional` scope:

```scala
libraryDependencies += "org.typelevel" %% "cats-effect" % Optional
```

The following ways of integration will work with `Optional` dependencies and degrade gracefully if the user does not
depend on an optional library:

* functions in top-level `object`s that mention optional types
* extension methods for your types that mention optional types
* extension methods and implicit conversions for your types to/from optional types

What won't work:

* non-orphan instances for optional typeclasses in your types' companion objects
* non-orphan instances for optional types in your typeclasses' companion objects

With `Optional` dependencies alone, we can already provide rich integrations with external libraries without forcing
unnecessary dependencies on those users that don't need them. If we don't need to define typeclass instances for optional
types or typeclasses, we can just add `Optional` dependencies and stop at that:

```scala
trait MyResource[F[_], A] {
  def acquire: F[A]
  def release(a: A): F[Unit]
}

// Users without a cats-effect dependency will be able to call `make` and any other methods,
// but won't see the implicit conversions.
// Users with cats-effect will get implicit syntax automatically without imports.
object MyResource {
  def make[F[_], A](acquire: F[A])(release: A => F[Unit]): MyResource[F, A] = new MyResource[F, A] { ... }

  // can define non-orphan extension methods
  implicit class ToCats[F[_], A](private val myResource: MyResource[F, A]) extends AnyVal {
    def toCats: cats.effect.Resource[F, A] = ...
  }

  // can define non-orphan implicit conversions
  implicit def fromCats[F[_], A](catsResource: cats.effect.Resource[F, A]): MyResource[F, A] = ...
}
```

Users without a `cats-effect` dependency will be able to call `make` and other methods, but won't be affected by implicit conversions:

```scala
val resource = MyResource.make(Try(1))(_ => Try(()))

resource.acquire
// ok

resource.toCats
// degrade gracefully with a compile error:

// Symbol 'type cats.effect.Resource' is missing from the classpath.
// This symbol is required by 'value mylib.MyResource.catsResource'.
// Make sure that type Resource is in your classpath and check for conflicting dependencies with `-Ylog-classpath`.
// A full rebuild may help if 'MyResource.class' was compiled against an incompatible version of cats.effect.
//     resource.toCats
```

But what about typeclasses?! What happens when we try to add an optional instance of a typeclass?

```scala
package mylib

trait MyMonad[F[_]] {
  def pure[A](a: A): F[A]
  def flatMap[A, B](fa: F[A])(f: A => F[B]): F[B]
}

case class MyBox[A](get: A)

object MyBox {

  implicit val myMonadForBox: MyMonad[MyBox] = new MyMonad[MyBox] {
    override def pure[A](a: A): MyBox[A] = MyBox(a)
    override def flatMap[A, B](fa: MyBox[A])(f: A => MyBox[B]): MyBox[B] = f(fa.get)
  }
  
  implicit val optionalCatsFunctorForMyBox: cats.Functor[MyBox] = new cats.Functor[MyBox] {
    def map[A, B](fa: MyBox[A])(f: A => B): MyBox[B] =
      MyBox(f(fa.get))
  }
}
```

Without a `cats` dependency, all implicit searches mentioning `MyBox` start failing! 

```scala
object WithoutCats {
  implicitly[MyMonad[MyBox]] // Symbol 'type cats.Functor' is missing from the classpath...
  implicitly[Ordering[MyBox[Int]]] // Symbol 'type cats.Functor' is missing from the classpath...
  implicitly[MyBox[Unit] =:= MyBox[Unit]] // Symbol 'type cats.Functor' is missing from the classpath...
}
```

Oh no, we broke Scala! Seems like our attempts at creating optional instances just end up breaking the compiler.

Why does Scalac break when trying to find implicits for `MyBox`? Following [implicit priority](http://eed3si9n.com/revisiting-implicits-without-import-tax),
the compiler will eventually try to search `MyBox`'s companion object for suitable implicits, it will check ALL implicit definitions,
and if it finds any classes it doesn't know about in implicits' arguments or result type, it will loudly complain and abort compilation.

To proceed, we need to fool Scalac somehow, we need a way to _hide_ the real type of our implicits when a required library is missing,
but at the same time _reveal_ the type if it's present, so that it can be picked up by the implicit search.


Optional Typeclass Instances
----------------------------

Naive ways of hiding the type won't work – generic parametrization _will_ successfully obscure the type  bytecode, the return type will become `java.Object`,
but the Scala compiler will see through it and crash anyway. 

```scala
object MyBox extends MyBoxFunctor[cats.Functor]

trait MyBoxFunctor[F[_[_]]] {
  implicit val optionalCatsFunctorForMyBox: F[MyBox] = new cats.Functor[MyBox] {
    def map[A, B](fa: MyBox[A])(f: A => B): MyBox[B] =
      MyBox(f(fa.get))
  }.asInstanceOf[F[MyBox]]
}
// [error] Symbol 'term <root>.cats' is missing from the classpath.
```

The type must be bound late, after Scalac's done inspecting `MyBox`'s implicits. We need a type-level function to provide
us the correct type when the library is present and pass otherwise. This function is surprisingly easy to write though!

```scala
class GimmeCatsFunctor[Functor[F[_]]]
object GimmeCatsFunctor {
  implicit val gimmeCatsFunctor: GimmeCatsFunctor[cats.Functor] = new GimmeCatsFunctor[cats.Functor] 
}
```

That's it. We can pass a type parameter to this implicit and it will "assign" `cats.Functor` to the parameter – effectively
we're going to use a 0-parameter version of the ['Aux pattern'](http://gigiigig.github.io/posts/2015/09/13/aux-pattern.html).

```scala
implicit def optionalCatsFunctorForMyBox[F[_[_]]](implicit gimme: GimmeCatsFunctor[F]): F[MyBox] = new cats.Functor[MyBox] {
  def map[A, B](fa: MyBox[A])(f: A => B): MyBox[B] =
    MyBox(f(fa.get))
}.asInstanceOf[F[MyBox]]
// works
```

This handles defining optional instances of _foreign_ typeclasses for library types. Instances of _library_ typeclasses for foreign types look similar:

```scala
object MyMonad {
  implicit def optionalMyMonadFromCatsMonad[F[_], M[_[_]]: CatsMonad](implicit m: M[F]): MyMonad[F] = {
    val M = m.asInstanceOf[cats.Monad[F]]
    new MyMonad[F] {
      override def pure[A](a: A): F[A] = M.pure(a)
      override def flatMap[A, B](fa: F[A])(f: A => F[B]): F[B] = M.flatMap(fa)(f)
    }
  }
}

private sealed trait CatsMonad[M[_[_]]]
private object CatsMonad {
  implicit val get: CatsMonad[cats.Monad] = null
}
```

After we 'assign' `M` to be `cats.Monad`, we summon it accordingly, then use `asInstanceOf` on the result since we already know the type underneath.
We never need an actual instance of `CatsMonad`, so we can set its instance to `null` and save our users a heap allocation.
Lastly, making all of this machinery `private` ensures there's no way to mess up our scheme and cause a failed cast. 

These two patterns let us define `Optional` non-orphan instances that will just work with no imports when users need them.

However, there's still a class of implicits that has to be treated specially – implicits that implement multiple
typeclasses, with signatures like `ClassA[T] with ClassB[T]`.

The Last Corner Case
----------------

Suppose we want to add another optional instance for `MyBox`, this time we'll implement multiple typeclasses with a single implicit:

```scala
object MyBox {
  implicit def optionalCatsSemigroupalSemigroupKInvariantForMyBox[F[_[_]]: CatsSemigroupalSemigroupKInvariant]: F[MyBox] = {
    new ImpllSemigroupalSemigroupKInvariant[MyBox] {
      def combineK[A](x: MyBox[A], y: MyBox[A]): MyBox[A] = y
      def product[A, B](fa: MyBox[A], fb: MyBox[B]): MyBox[(A, B)] = MyBox((fa.get, fb.get))
      def imap[A, B](fa: MyBox[A])(f: A => B)(g: B => A): MyBox[B] = MyBox(f(fa.get))
    }.asInstanceOf[F[MyBox]]
  }
}

trait ImpllSemigroupalSemigroupKInvariant[K[_]] extends cats.Semigroupal[K] with cats.SemigroupK[K] with cats.Invariant[K]

private sealed trait CatsSemigroupalSemigroupKInvariant[F[_[_]]]
private object CatsSemigroupalSemigroupKInvariant {
  implicit val get: CatsSemigroupalSemigroupKInvariant[ImpllSemigroupalSemigroupKInvariant] = null
}
```

That seems to work fine at first, we can summon this instance in a project with cats:

```scala
object WithCats {
  implicitly[SemigroupK[MyBox]]
  implicitly[Semigroupal[MyBox]]
}
```

However, a project without cats would break down when using any implicits for `MyBox`:

```scala
object WithoutCats {
  implicitly[MyMonad[Box]]
}
// [error] Symbol 'type cats.Semigroupal' is missing from the classpath.
// [error] This symbol is required by 'trait mylib.ImpllSemigroupalSemigroupKInvariant'.
```

The problem is that trait `ImpllSemigroupalSemigroupKInvariant` is defined in _our_ library, not externally. Scalac will always
find it successfully, inspect it, and notice it's broken since its superclasses are missing from the classpath.

Changing this trait to a type alias won't work either:

```scala
private object CatsSemigroupalSemigroupKInvariant {
  type ImpllSemigroupalSemigroupKInvariant[K[_]] = cats.Semigroupal[K] with cats.SemigroupK[K] with cats.Invariant[K]
  implicit val get: CatsSemigroupalSemigroupKInvariant[ImpllSemigroupalSemigroupKInvariant] = null
}
// [error] Symbol 'type cats.Semigroupal' is missing from the classpath.
// [error] This symbol is required by 'type mylib.CatsSemigroupalSemigroupKInvariant.ImpllSemigroupalSemigroupKInvariant'.
```

As before, Scalac always finds the type alias and looks inside it, breaking our scheme. One other option we have available
is to move this trait to a separate module `mylib-cats-support` and depend on it Optionally in our core module. If the user
adds this module, they'll have cats instances, otherwise they won't even if they have a cats dependency. But that would
just trade one inconvenience for another! Sure, we don't have to import orphans in every file anymore, but we'd still have
to find and include a special integration module. There must be a way to define an optional composite instance without creating
a separate module.

To do that, we need to add a guarding implicit before we reveal the type of `CatsSemigroupalSemigroupKInvariant`:

```scala
private sealed trait CatsSemigroupalSemigroupKInvariant[F[_[_]]]
private object CatsSemigroupalSemigroupKInvariant {
  implicit def get(implicit haveCats: CatsIsAvailable): CatsSemigroupalSemigroupKInvariant[ImpllSemigroupalSemigroupKInvariant] = null
}

private sealed trait CatsIsAvailable
private object CatsIsAvailable {
  implicit def get[F[_[_]]: GimmeCatsFunctor]: CatsIsAvailable = null
}
```

An instance of `CatsIsAvailable` will exist only if `GimmeCatsFunctor` – a typeclass we defined previously to reveal `cats.Functor` –
summons succesfully, which will only happen if `cats` is a dependency of the current project.
We can mention `ImpllSemigroupalSemigroupKInvariant` in a type argument of the result, since it won't be inspected deeply
until the implicit is actually considered – and the `haveCats` guard ensures it won't be considered unless it's correct.

We've unbroken the non-cats project now:

```scala
object WithoutCats {
  implicitly[MyMonad[Box]] // success!
}
```

There's one minor oddity left, our instance is not being found when summoned as an intersection type:

```scala
object WithCats {
  implicitly[Invariant[MyBox] with Semigroupal[MyBox]]
}
// [error] could not find implicit value for parameter e: cats.Invariant[mylib.MyBox] with cats.Semigroupal[mylib.MyBox]
// [error] implicitly[Invariant[MyBox] with Semigroupal[MyBox]]
```

This time it's an actual [scala bug](https://github.com/scala/bug/issues/11502).

Fortunately for us, it can be fixed by seemingly no-op transformations, such as declaring result type as `X with X`,
applying `type Id[A] = A` type alias or presumably with any other construct that actually does nothing to the type:

```scala
type OptionalInstance[A] = A
implicit def optionalCatsSemigroupalSemigroupKInvariantForMyBox[F[_[_]]: CatsSemigroupalSemigroupKInvariant]: OptionalInstance[F[MyBox]]
```

```scala
object WithCats {
  implicitly[Invariant[MyBox] with Semigroupal[MyBox]] // success!
}
```


Extracting a pattern
--------------------

It may be tedious to create a new class for each foreign type we want to declare optional instances for, we can extract
the pattern into reusable pieces and get rid of `asInstanceOf` calls in the process by carefully crafting equality evidence.
You may find one possible [implementation](https://github.com/7mind/no-more-orphans/blob/master/mylib/src/main/scala/mylib/pattern/GetTc.scala)
of this pattern in the [companion repository](https://github.com/7mind/no-more-orphans) for this blog post. The repository
also hosts the final versions of [`MyBox`](https://github.com/7mind/no-more-orphans/blob/master/mylib/src/main/scala/mylib/MyBox.scala)
and [`MyMonad`](https://github.com/7mind/no-more-orphans/blob/master/mylib/src/main/scala/mylib/MyMonad.scala) and a test suite showcasing correct implementation of the pattern.

What libraries currently use this pattern?

- [logstage](https://izumi.7mind.io/latest/release/doc/logstage/index.html) - uses this trick to provide `cats` and `ZIO`-friendly structural logging algebras out of the box without making either a mandatory dependency.
- [distage](https://izumi.7mind.io/latest/release/doc/distage/index.html) - uses it to support dependency injection [for](https://izumi.7mind.io/latest/release/doc/distage/basics.html#resource-bindings-lifecycle) [cats.effect.Resource](https://typelevel.org/cats-effect/datatypes/resource.html), cats `IO` and `ZIO` out-of-the-box, while still being perfectly usable without effect wrappers.

We hope more libraries follow and reduce the wildcard import tax on the community in favor of optional typeclass instances! 
