.. Kataglyphis-CMakeTemplate documentation master file, created by
   sphinx-quickstart on Mon Jun  2 09:39:40 2025.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

Kataglyphis-CMakeTemplate documentation
=======================================

.. rst-class:: hero-section

Modern C++ template with CMake, tests, benchmarks, and generated API docs.

- Fast setup with presets
- Integrated API + Graphviz diagrams
- Human-friendly CI test result pages

.. grid:: 2
   :gutter: 2

   .. grid-item-card:: Getting Started
      :link: getting-started
      :link-type: doc

      Build, run and test quickly with the predefined presets.

   .. grid-item-card:: Library API
      :link: api/library_root
      :link-type: doc

      Browse generated API references from Doxygen + Breathe + Exhale.

   .. grid-item-card:: Graphviz Diagrams
      :link: graphviz_files
      :link-type: doc

      Visual dependency and include graphs for fast architectural orientation.

   .. grid-item-card:: Test Results
      :link: test-results/index
      :link-type: doc

      Converted and browsable test reports for CI and local runs.


.. toctree::
   :maxdepth: 2
   :caption: Contents:
   :titlesonly:

   api/library_root
   graphviz_files

Coverage
========

* `Coverage report <coverage/index.html>`_

Test results
============

* `Test results (JUnit XML viewer) <test-results/>`_

.. toctree::
   :maxdepth: 2
   :caption: Contents:

   introduction
   getting-started
   test-results/index

Indices and tables
==================

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`
