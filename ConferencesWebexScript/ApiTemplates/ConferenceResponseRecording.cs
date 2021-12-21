using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace ConferencesWebexScript.ApiTemplates
{
    internal class ConferenceResponseRecording
    {
        public bool locked { get; set; }
        public bool recordingStarted { get; set; }
        public bool recordingPaused { get; set; }
    }
}
