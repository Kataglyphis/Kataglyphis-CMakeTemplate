
.. _program_listing_file_Src_Main.cpp:

Program Listing for File Main.cpp
=================================

|exhale_lsh| :ref:`Return to documentation for file <file_Src_Main.cpp>` (``Src/Main.cpp``)

.. |exhale_lsh| unicode:: U+021B0 .. UPWARDS ARROW WITH TIP LEFTWARDS

.. code-block:: cpp

   #include "KataglyphisCppProjectConfig.hpp"
   #include <iostream>
   
   extern "C" {
   int32_t rusty_extern_c_integer();
   }
   
   int main()
   {
       if (USE_RUST) { std::cout << "A value given directly by extern c function " << rusty_extern_c_integer() << "\n"; }
       std::cout << "Hello World! " << "\n";
       return 0;
   }
