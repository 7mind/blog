Monorepo or Multirepo? Role-Based Repositories
==============================================

## Summary

When you have a lot of code it's always hard to find a proper approach organize your code.

Typically engineers choose between monorepo and multirepo layouts. Both approaches have well-known
advantages and disadvantages which significantly affects team productivity.

It's possible to establish a combined workflow, keeping all the advantages of multirepo layout but
not giving up any positive traits of monorepo layout.

We created a draft of a tool implementing our approach for Scala projects using SBT.

## The problem

### Monorepo: good and bad

Good points of monorepo layout are:

1. **Coherence**: you always have coherent codebase which represents all your work.
   You may build all the components of your product together and had good guarantees
   of their compatibility.
   When you make a change and your build finishes your are fine, you don't have to
   modify and test any other repository/component which may be affected by your change,
   you may always
2. **Cheap workflows**: you may use just one CI job, you can easily release and deploy
   your components together, you may easily refactor the code.

But there are significant shortcomings:

1. **Isolation**: monorepo does not prevent engineers from using the code
   they should not use. So, big projects in a monorepo have a tendency to
   degrade and become unmaintainable over time.
   It's possible to enforce a strict code review and artifact layouting preventing
   such a degradation but it's not easy and it's time consuming,
2. **Build time**: in case you have a monolithic project in a monorepo you have to
   build (and often test) all the components together. It may be addressed by an
   incremental compiler but it does not solve all the issues. Also it may be addressed
   by keeping independent projects within one repository but in that case most of the
    multirepo shorcomings (see below) apply,
3. **Merge conflicts**: teams working in monorepo environment have to maintain a good VCS
   flow to avoid interference. While it's a very good idea to teach engineers how to use
   GIT properly, the discipline doesn't come for free.
4. **VCS actions take time**: when you host a huge project (like Chromium) in GIT it may
   take a lot of time even to perform a checkout. This affects only huge projects and huge teams
   so it's outside of the scope of this post.

### Multirepo: good and bad

Monorepo layout is always considered as a first answer to any multirepo issues because:

1. It enforces strict isolation between independent software components,
2. It allows people to quickly build independent components,
3. It allows people not to interfere while working on independent projects.

Though monorepo is a disaster:

1. **Global refactorings affecting** a shared component is a real pain, even simple rename cannot
   be done in one click,
2. It's may be hard to perform any kind of **integration**. When you have multiple components you
   have to build a comprehensive orchestration solutions for your integration testing and deployments,
   you have to setup sophisticated CI flows, etc, etc,
3. In case your release flow involves several components - it's always a real pain in the ass.

These things are especially bad when you have some explicit or implicit dependencies between your
components which is a typical case, usually we have at least one shared library (aka SDK) and many
or all our components (aka microservices) depend on that library.

## The solution


### SBT and it's shortcomings

### sbtgen: a prototype of RBR-flow tool

### Things to do
