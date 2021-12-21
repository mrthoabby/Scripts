using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace ConferencesWebexScript.Entities
{
    public class DataCreate : ConferencingParameters
    {
        public string Start_time { get; set; } 
        public string End_time { get; set; }

    }
}
