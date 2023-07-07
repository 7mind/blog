---
layout: post
tags: [plt]
---

What is an “Effect” in Functional Programming?
==============================================

People often use the terms "effect" and "side effect" when working with functional programming languages.

Newbies and people with different PL backgrounds often ask what these terms mean. Surprisingly, different people in different contexts may mean different things when they use these terms. That induces endless confusion and holy wars.

If you ask ChatGPT this question, it might answer something like

> In functional programming, the term “effect” refers to any observable change or interaction that a function or expression can have with the outside world beyond its return value. Effects include actions such as input/output (I/O) operations, mutation of state, network requests, and interactions with external resources like databases or files. An effect is a deviation from the purely functional paradigm, where a function’s behavior is solely determined by its inputs and produces a predictable output. In contrast, an effect introduces an element of uncertainty or nondeterminism, as it may depend on external factors or have side effects that alter the program’s state or interact with the environment.

Thus, ChatGPT thinks that an “Effect” means “breakage of referential transparency”.

If you [check StackOverflow](https://stackoverflow.com/a/33398273) you might see that some people think that “breakage of referential transparency” should be called “Side-Effect”, while “Effect” should stand for something what “distinguishes between the actual value and the ‘rest’“ of an abstraction. Wait, what?

Some people may [quote](https://stackoverflow.com/a/49132391) an [original paper](http://homepages.inf.ed.ac.uk/wadler/topics/monads.html) which says

> In general, a function of type a → b is replaced by a function of type a → M b. This can be read as a function that accepts an argument of type a and returns a result of type b, with a possible additional effect captured by M. This effect may be to act on state, generate output, raise an exception, or what have you.

Some people might just refer to [an IO-monad](https://typelevel.org/cats-effect/docs/getting-started) as an “Effect” and the same people might give us a [definition](https://typelevel.org/cats-effect/docs/concepts#effects) for “Effect” as vague as

> An effect is a description of an action (or actions) that will be taken when evaluation happens. One very common sort of effect is IO.

So, things may go *wild* when we chat about effects.

I would like to make yet another clarification for this.

Essentially, there are two different ways to speak about effects. There is the Haskell community way, which was probably introduced by the paper linked above. And there is the way cyberneticians spoke and people in robotics and medicine still [speak](https://pubmed.ncbi.nlm.nih.gov/17149592/).

In my opinion, the Haskell way to name things is an unfortunate deviation we have to live with.

So, let’s try to have a closer look at the problem. When we deal with abstractions and functions, we want to reason about them. For example, if we know that some function is “Total”, we may be sure that it would never loop and would always return the same result for the same arguments. So, our runtime might “memoize” the outputs of such functions and even directly substitute calls with pre-computed parameters. “Pure” functions are, essentially, the same, with the only difference that they might loop forever. Impure functions may return the different results for the same input, violating referential transparency. Modern Haskell way to refer to such functions is to say that they “have Side-Effects”.

So, what is actually an “Effect” in Haskell? Essentially, that is what most of the programmers used to call “Aspect” — any property additional to a primary concept. Yes, that *is* very abstract. Considering `Either[L, R]` in Scala, it can be said that it produces an effect, allowing the return of errors of type `L` from functions with results of type `R`. `Either` is [“right-biased”](https://www.scala-lang.org/api/2.12.7/scala/util/Either.html). The property of returning an error is an additional property encoded by Either. We can define `type Alternative[L, R] = L | R` without it being an effect because it is unbiased and both sides are equally probable. At the same time one might define such a type in a programming language which supports unions but does not support type constructors and maintain the bias by convention. In that case it would be fine to call our `Alternative` an Effect.

There is also “Unwanted Side-Effect” in Haskell terminology. It is some unwanted but observable breakage of some contract caused by leaking abstractions in the programming model. A computation with tight timing could fail because of another running in parallel that uses up resources.

I should stress that “Unwanted Side-Effect” aren’t necessarily “Side-Effects" (it’s not necessarily a breakage of referential transparency) while “Side-Effects” have nothing in common with “Effects”.

Is there a less obscure way to refer to these things? Yes, there is, and, moreover, it's widely used but not in the domain of functional programming.

What Haskell people call "Effect" has a less obscure name **Aspect**. Moreover, it is being [used](https://en.wikipedia.org/wiki/Aspect-oriented_programming) by many programmers with exactly the same semantic.

What Haskell people call "Unwanted side effect" should be called just **Side-Effect**.  This term has a very stable semantic in [medicine](https://en.wikipedia.org/wiki/Side_effect) and engineering. A **Side-Effect** is always "unwanted" in these domains. But not in Haskell nor Computer Science world.

It is interesting what to do with "Side-Effects" in Haskell. We might notice that there are two important classes of "Side-Effects". A function might violate referential transparency by "reading" from an "external state" or by "writing" into it. Or, of course, by both. If we check robotics, cybernetics and medicine, we would find two concepts called "afferent channel" meaning a way for a system, robot or an organism to percept information from the outside world and "efferent channel" which stand for a capability of a system, robot or an organism to change, mutate the world outside. These terms come from two words with Latin roots, ["Effect" and "Affect"](https://www.merriam-webster.com/words-at-play/affect-vs-effect-usage-difference). Three big scientific domains use these terms in their original meaning. Including a domain which predates Computer Science. So, I think that Computer science should do the same and call "reading" referential transparency violations, when outside world "changes" the function state, **Affects**, and, vice-versa, call changes made by a function to the world outside **Effects**.

Alike to **Effects** and **Affects** we might split **Side Effects** into two classes, **Side-Effects** and **Side-Affects**. **Side-Effects** would mean an accidental unwanted mutation and **Side-Affects** would stand for a program being unwantedly affected by something from outside of the abstraction in use.

Here is a short table of the harmonized terms.


| Haskell Term         | Meaning                                                                                                                | Harmonized term                     |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| Effect               | Abstract additional property to a primary concept                                                                      | **Aspect**                          |
| Side-Effect          | Referential transparency violation                                                                                     | **Effect** and **Affect**           |
| Unwanted side effect | Unintended violation of important contract caused by leaking abstractions in programming model, runtime, hardware, etc | **Side-Effect** and **Side-Affect** |
