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

### The idea

Let's assume that we have a product (an online auction platform, for example) consisting of several software components:

1. `iam`: Identity and Account Management Service
2. `billing`: Billing Service
3. `analytics`: Analytics Service
4. `bidding`: Bidding Service
5. `catalog`: Item Catalog Service

All these projects use one shared SDK named `sdk`.

We may also assume that there would be several teams working on these projects.
For example we may assign `sdk`, `iam` and `catalog` projects to "infrastructure" team,
`billing` and `analytics` to "finance" team and `bidding` to "store" team.

Imagine that you have a magic tool `project` allowing us to choose which
projects we want to work on and set up the environment:

```bash
# Prepares workspace for all our components
project prepare *

# Prepares workspace to work on `billing` and `analytics`
# Pulls in `sdk` as well
project prepare +billing +analytics

# Prepares workspace to work on `sdk`, `iam` and `catalog`
project prepare :infrastructure

# Prepares cross-build project
project prepare --platforms js,jvm,native :infrastructure
```

This tool would need some kind of declarative description of our product stored in a repository.
The rest can be as flexible as we wish. For example, in case we don't want to keep all our source code in one repository,
the tool may pull the components from different repositories, take care of commits, etc, etc.

We may say that our repository have *roles* and at any time we may choose which roles we wish to *activate*.
So, we may call this approach "Role-Based Repository", or RBR.

Such a tool would solve most of the problems. When we need to perform a global refactoring we may generate all-in-one project.
When we wish to implement a quick patch we may generate a project with just one component.
When we need to integrate several components we may choose what exactly we need. Etc, etc.

### The reality

Unfortunately, there is no such a tool which is polyglot, convenient and easy to use.
Something can be done with Bazel, but as far as I know there are no good solutions at this moment
(October 2019).

And things become bad when we need this for Scala. And especially bad when we need to work with cross-platform Scala environments
(ScalaJS and Scala Native).

### SBT and IntellijIDEA

There is no sane way to exclude some projects from an SBT build according to some criteria. You may write something like

```scala
lazy val conditionalProject = if (condition) {
  project.in(...)
} else {
  null
}
```

But it's ugly, inconvenient and hard to compose.

And cross-platform projects were always a pain. It takes at least twice more time to build a cross-project.
And there is no way to, for example, omit all the ScalaJS projects from a build.

For example, IDEA frequently [fails](https://youtrack.jetbrains.com/issue/SCL-16128) to compile any projects
if `sbt-crossproject` plugin is on. IDEA [cannot run tests](https://youtrack.jetbrains.com/issue/SCL-14640)
in cross-projects. And so on.

SBT builds become very verbose and hard to maintain when you use cross-projects.
Usually you have to write at least 3 redundant expressions per artifact.

### sbtgen: a prototype of RBR-flow tool

We've created our own [dirty tool](https://github.com/7mind/sbtgen) which prototypes the approach we wish to have.
Essentially, it's a library intended to be used in an [ammonite script](https://ammonite.io/#ScalaScripts) which takes
declarative project definitions and emits SBT build files.

You may find a real project using it [here](https://github.com/7mind/izumi).
In case you want to play with it you would need [Coursier](https://get-coursier.io/) installed.
After you clone the project you may try the following commands:

```bash
# generates pure JVM project
./sbtgen.sc

# generates JVM/JS cross-project
./sbtgen.sc --js

# generates pure JVM project for just one of our components
./sbtgen.sc -u distage
```

Currently `sbtgen` is a very simple and dirty prototype but it made our team happy.
Now it's easy to release, when we need it we may choose what to work on, what to build and what to test.
Also, surprisingly, SBT startup time is lot shorter when we generate our projects instead of using
sophisticated plugins to avoid settings duplication.

I don't encourage you to use `sbtgen`, but next time you think about organizing your code try to consider RBR flow even
if you would have to write your very own code generator.

I may say for sure that you will not be disappointed.

### Things to do

1. `sbtgen` needs to support multi-repository layouts. At this point all the source code needs to be kept together with the build descriptor,
2. I think such functionality should be incorporated into SBT. There are some plugins ([sbt-projectmatric](http://eed3si9n.com/parallel-cross-building-using-sbt-projectmatrix) and [siracha](http://eed3si9n.com/hot-source-dependencies-using-sbt-sriracha)) which make SBT projects kinda configurable and less rigid but they are very far from what we actually need.
